import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TrainingSession, chooseBotMove, legalMoves } from '../js/bot.js';
import { createMatch, cloneMatch, resolveTick, isValidCommand, TICKS } from '../js/rules.js';

test('all bot levels make legal moves without changing the public board', () => {
  const match = createMatch();
  resolveTick(match, { platform: 0, dir: 1 }, { platform: 1, dir: -1 });
  const before = cloneMatch(match);
  for (const difficulty of ['easy', 'medium', 'hard']) {
    assert.equal(isValidCommand(match, chooseBotMove(match, difficulty)), true);
    assert.deepEqual(match, before);
  }
  assert.equal(legalMoves(match).length, 15);
  assert.equal(chooseBotMove(match, 'easy', () => 0), null);
});

test('training completes locally with automatic bot turns and a final result', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  let finished = 0;
  let resolved = 0;
  const session = new TrainingSession({ map: 0, difficulty: 'medium' }, {
    decideMs: 10,
    resolved(event) { resolved++; assert.equal(event.tick, resolved); },
    finished() { finished++; },
  });
  session.connected();
  for (let i = 0; i < TICKS && !session.ended; i++) {
    assert.equal(session.phase, 'decide');
    const bot = session.botMove;
    session.choose(legalMoves(session.match)[1]);
    assert.deepEqual(session.botMove, bot, 'bot cannot react to the human selection');
    t.mock.timers.tick(10);
    await Promise.resolve();
  }
  assert.equal(session.ended, true);
  assert.equal(finished, 1);
  assert.equal(session.match.finished, true);
  session.dispose();
});

test('strategic levels preserve an immediate delivery to the bot receiver', () => {
  for (const difficulty of ['medium', 'hard']) {
    const match = createMatch();
    match.tick = 2;
    match.cells[0][0] = 5; // Vertical track, ready to deliver upwards.
    match.balls = [{ id: 1, row: 0, col: 0, exit: 0 }];
    resolveTick(match, chooseBotMove(match, difficulty), null);
    assert.equal(match.score.top, 1);
  }
});

test('training locks the final drag before resolve and never restarts after disposal', async t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
  let release;
  let event;
  const command = { platform: 0, dir: 1 };
  const session = new TrainingSession({ map: 0, difficulty: 'easy' }, {
    decideMs: 10,
    lock() { session.choose(command); },
    resolved(result) { event = result; return new Promise(resolve => { release = resolve; }); },
  });
  session.connected();
  t.mock.timers.tick(10);
  assert.deepEqual(event.commands.bottom, command);
  session.dispose();
  release();
  await Promise.resolve();
  t.mock.timers.tick(100);
  assert.equal(session.phase, 'disposed');
  assert.equal(session.match.tick, 1);
});

test('leaving during decision cancels the bot timer', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const session = new TrainingSession({ map: 0, difficulty: 'easy' }, { decideMs: 10 });
  session.connected();
  session.dispose();
  t.mock.timers.tick(100);
  assert.equal(session.match.tick, 0);
});
