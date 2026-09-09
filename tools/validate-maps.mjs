import { MAPS, createMatch, resolveTick, TICKS, SIZE } from "../js/rules.js";

// Random-play probe: do deliveries happen for both sides across many matches?
function rng(seed){ let s=seed; return ()=> (s=(s*1103515245+12345)&0x7fffffff)/0x7fffffff; }

for (let mi=0; mi<MAPS.length; mi++) {
  let topGoals=0, bottomGoals=0, stuckTicks=0, totalTicks=0, matchesNoGoal=0;
  const RUNS=300;
  for (let run=0; run<RUNS; run++) {
    const r = rng(run*7919+1);
    const m = createMatch(mi);
    let goals=0;
    while(!m.finished){
      const mk=()=>{ if(r()<0.15) return null;
        let p; let guard=0;
        do { p=Math.floor(r()*9); guard++; } while(m.cooldown.includes(p)&&guard<20);
        return m.cooldown.includes(p)?null:{platform:p,dir:r()<0.5?1:-1}; };
      const ev = resolveTick(m, mk(), mk());
      totalTicks++;
      if(ev.moves.every(x=>x.kind==="wait") && ev.moves.length>0) stuckTicks++;
      goals += ev.delivered.length;
    }
    topGoals+=m.score.top; bottomGoals+=m.score.bottom;
    if(goals===0) matchesNoGoal++;
  }
  console.log(`${MAPS[mi].name.padEnd(10)} top=${(topGoals/RUNS).toFixed(2)} bottom=${(bottomGoals/RUNS).toFixed(2)} avg/match=${((topGoals+bottomGoals)/RUNS).toFixed(2)} stuckTicks=${(100*stuckTicks/totalTicks).toFixed(1)}% matchesWithNoGoal=${(100*matchesNoGoal/RUNS).toFixed(1)}%`);
}
