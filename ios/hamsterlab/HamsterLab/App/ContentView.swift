import SwiftUI
import RealityKit

private let mint = LabTheme.teal
private let coral = LabTheme.berry
private let muted = LabTheme.secondaryInk

struct ContentView: View {
    @ScaledMetric(relativeTo:.largeTitle) private var titleSize = 58.0
    @GestureState private var boardTouchActive = false
    @Bindable var game: GameModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: Panel?
    @State private var code = ""
    @State private var invalidJoinCode = false
    @State private var confirmLeave = false
    @State private var incomingCode: String?
    enum Panel: Identifiable {
        case setup(String), settings, rules, privacy
        var dismissTitleKey: String {
            switch self {
            case .setup("training"), .setup("join"), .setup("host"): "native.back"
            default: "native.done"
            }
        }
        var id: String {
            switch self {
            case .setup(let mode): "setup-\(mode)"
            case .settings: "settings"
            case .rules: "rules"
            case .privacy: "privacy"
            }
        }
    }
    var body: some View {
        ZStack {
            background
            if let bridge = game.bridge { ProtocolHost(bridge:bridge).frame(width:1,height:1).opacity(0.01).accessibilityHidden(true).allowsHitTesting(false) }
            GeometryReader { geometry in
                let wide = geometry.size.width > 760 && geometry.size.width > geometry.size.height
                VStack(spacing:0) {
                    topBar.padding(.horizontal,24).padding(.top,12).padding(.bottom,8)
                    switch game.screen {
                    case .menu: menu(wide:wide, size:geometry.size)
                    case .lobby: lobby
                    case .game, .result: arena(wide:wide, size:geometry.size)
                    }
                }
                .frame(maxWidth:1200).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .font(.system(.body,design:.rounded))
        .fontDesign(.rounded)
        .foregroundStyle(LabTheme.ink)
        .tint(mint)
        .sheet(item:$sheet) { panel in
            NavigationStack {
                Group {
                    switch panel {
                    case .setup(let mode): setup(mode:mode)
                    case .settings: settings
                    case .rules: rules
                    case .privacy: privacy
                    }
                }
                .scrollContentBackground(.hidden)
                .background(LabTheme.canvas)
                .foregroundStyle(LabTheme.ink)
                .fontDesign(.rounded)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button(L(panel.dismissTitleKey)) { sheet = nil }.accessibilityIdentifier("sheet.done") } }
                .toolbarBackground(LabTheme.canvas,for:.navigationBar)
                .toolbarBackground(.visible,for:.navigationBar)
            }.presentationDetents([.large]).preferredColorScheme(.light).tint(mint)
        }
        .alert(L("native.notice"),isPresented:Binding(get:{game.error != nil},set:{if !$0 {game.error=nil}})) {
            Button(L("native.done"),role:.cancel) { game.error = nil }
        } message: { Text(game.error ?? "") }
        .confirmationDialog(L("native.leaveQuestion"),isPresented:$confirmLeave,titleVisibility:.visible) {
            Button(L("native.leave"),role:.destructive) {
                game.leave()
                if let incomingCode { code = incomingCode; self.incomingCode = nil; sheet = .setup("join") }
            }
            Button(L("action.cancel"),role:.cancel) { incomingCode = nil }
        }
        .onChange(of:scenePhase, initial:true) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
            if phase == .active { game.foreground() }
            else if phase == .background { game.background() }
        }
        .onChange(of:reduceMotion) { _,_ in
            game.boardScene.refreshMotionPreferences()
        }
        .onOpenURL { acceptInvitation($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { acceptInvitation(url) }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                game.name = "Explorer"
                AudioEngine.shared.enabled = false
                if ProcessInfo.processInfo.arguments.contains("--training") || ProcessInfo.processInfo.arguments.contains("--autoplay") { game.startTraining() }
                if ProcessInfo.processInfo.arguments.contains("--lab-preview") {
                    game.startTraining()
                    game.board = BoardState(map:0)
                    game.board.nextBallId = 5
                    game.board.balls = [Ball(id:1,row:2,col:2,exit:0),Ball(id:2,row:3,col:3,exit:2),Ball(id:3,row:0,col:1,exit:1),Ball(id:4,row:4,col:4,exit:2)]
                    game.boardScene.render(game.board,side:.bottom)
                }
                if ProcessInfo.processInfo.arguments.contains("--home-arrival") {
                    game.startTraining()
                    var fixture=BoardState(); fixture.tick=2
                    fixture.score.top=2; fixture.score.bottom=2
                    fixture.cells[0][0]=5; fixture.cells[5][5]=5
                    fixture.balls=[Ball(id:21,row:0,col:0,exit:0),Ball(id:22,row:5,col:5,exit:2)]
                    fixture.nextBallId=23
                    game.board=fixture; game.boardScene.render(fixture,side:.bottom)
                    try? await Task.sleep(for:.milliseconds(700))
                    guard game.screen == .game else { return }
                    var after=fixture
                    let turn=Rules.resolve(&after,top:nil,bottom:nil)
                    game.board=after
                    game.boardScene.animate(before:fixture,after:after,turn:turn,side:.bottom)
                }
                if ProcessInfo.processInfo.arguments.contains("--autoplay") {
                    await game.autoplayTraining()
                }
            }
        }
    }
    private func acceptInvitation(_ url: URL) {
        guard let value = game.handleURL(url) else { return }
        if game.screen == .menu { code = value; sheet = .setup("join") }
        else { incomingCode = value; confirmLeave = true }
    }
    private var background: some View {
        LabTheme.canvas.ignoresSafeArea()
    }
    private var topBar: some View {
        HStack {
            if game.screen != .menu {
                Button { confirmLeave = true } label: { Image(systemName:"chevron.left").frame(width:44,height:44) }
                    .accessibilityLabel(L("native.leave")).accessibilityIdentifier("game.leave")
            } else {
                Text(L("meta.title"))
                    .font(.headline.weight(.heavy)).foregroundStyle(mint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button { sheet = .rules } label: { Image(systemName:"questionmark.circle").frame(width:44,height:44) }
                .accessibilityLabel(L("menu.how"))
            Button { sheet = .settings } label: { Image(systemName:"slider.horizontal.3").frame(width:44,height:44) }
                .accessibilityLabel(L("native.settings")).accessibilityIdentifier("menu.settings")
        }.foregroundStyle(muted)
    }
    @ViewBuilder private func menu(wide: Bool, size: CGSize) -> some View {
        ScrollView {
            if wide {
                HStack(spacing:50) { menuIntro; menuArt.frame(maxWidth:520) }.padding(40)
            } else {
                VStack(spacing:22) {
                    title
                    menuArt.frame(height:min(size.height*0.31,300))
                    menuActions
                }.padding(.horizontal,28).padding(.top,12).padding(.bottom,24).frame(maxWidth:560).frame(maxWidth:.infinity)
            }
        }.scrollIndicators(.hidden)
    }
    private var title: some View {
        VStack(spacing:12) {
            HStack(spacing:8) { Image(systemName:"sparkles"); Text(L("native.eyebrow")) }.font(.caption.weight(.bold)).foregroundStyle(mint)
            Text(L("meta.title")).font(.system(size:titleSize,weight:.black,design:.rounded)).tracking(-2)
                .foregroundStyle(mint)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(L("lab.tagline"))
                .font(.subheadline).foregroundStyle(muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var menuIntro: some View { VStack(spacing:30) { title; menuActions }.frame(maxWidth:420) }
    private var menuArt: some View {
        Image("MenuHamsters")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
    private var menuActions: some View {
        VStack(spacing:12) {
            Button { sheet = .setup("online") } label: {
                HStack { Image(systemName:"globe.europe.africa.fill"); Text(L("menu.online")); Spacer(); Image(systemName:"arrow.right") }
            }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("menu.online")
            HStack(spacing:12) {
                Button { sheet = .setup("host") } label: {
                    Label(L("menu.friend"),systemImage:"person.2.fill").frame(maxWidth:.infinity)
                }.buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("menu.friend")
                Button { sheet = .setup("training") } label: {
                    Label(L("menu.training"),systemImage:"sparkles").frame(maxWidth:.infinity)
                }.buttonStyle(GameButtonStyle(secondary:true,playful:true)).accessibilityIdentifier("menu.training")
            }
            Button { sheet = .setup("join") } label: {
                Label(L("native.haveCode"),systemImage:"link").font(.subheadline.weight(.semibold)).padding(10)
            }.accessibilityIdentifier("menu.join")
            if game.hasSavedGame {
                Button { game.resume() } label: { Label(L("native.resume"),systemImage:"arrow.clockwise").frame(maxWidth:.infinity) }
                    .buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("menu.resume")
            }
        }
    }
    private var lobby: some View {
        ScrollView {
            VStack(spacing:28) {
                Image(systemName:game.showsRoomInvitation ? "person.2.wave.2.fill" : "globe.europe.africa")
                    .font(.system(size:70)).foregroundStyle(mint).padding(.top,60)
                Text(L(game.showsRoomInvitation ? "lobby.created" : "status.finding")).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(game.status).foregroundStyle(muted).multilineTextAlignment(.center)
                ProgressView().tint(mint)
                if game.showsRoomInvitation {
                    Text(game.roomCode).font(.system(size:44,weight:.heavy,design:.monospaced)).tracking(8)
                        .textSelection(.enabled).accessibilityIdentifier("lobby.code")
                    ShareLink(item:game.inviteURL) { Label(L("native.share"),systemImage:"square.and.arrow.up").frame(maxWidth:.infinity) }
                        .buttonStyle(GameButtonStyle())
                    Button { UIPasteboard.general.url = game.inviteURL; game.status = L("status.copied") } label: { Label(L("action.copy"),systemImage:"doc.on.doc") }
                } else if game.onlineCount > 0 {
                    Text("\(L("name.online")) \(game.onlineCount)").foregroundStyle(muted)
                }
                Button(L("action.cancel")) { game.leave() }.padding()
            }.padding(28).frame(maxWidth:500).frame(maxWidth:.infinity)
        }
    }
    private func arena(wide: Bool, size: CGSize) -> some View {
        ScrollViewReader { scroll in
            Group {
                if wide {
                    HStack(spacing:24) {
                        boardView.frame(maxWidth:.infinity,maxHeight:.infinity)
                        ScrollView { VStack(spacing:22) { scoreboard; turnControls; if game.screen == .result { resultCard } }.padding(20) }.frame(width:320)
                    }.padding(.horizontal,24).padding(.bottom,16)
                } else {
                    GeometryReader { viewport in
                        ScrollView {
                            VStack(spacing:12) {
                                scoreboard.padding(.horizontal,24)
                                Spacer(minLength:0)
                                VStack(spacing:12) {
                                    // Fit by width so a short viewport does not narrow the board.
                                    boardView.frame(width:viewport.size.width,height:viewport.size.width*828/720)
                                    if game.screen == .result { resultCard.padding(.horizontal,24).frame(maxWidth:700) }
                                    else { turnControls.padding(.horizontal,24).frame(maxWidth:700) }
                                }
                                Spacer(minLength:0)
                            }
                            .padding(.bottom,24)
                            // Share spare height above and below the play area, while
                            // allowing compact screens and larger text to scroll.
                            .frame(minHeight:viewport.size.height)
                            .frame(maxWidth:.infinity)
                        }.scrollIndicators(.hidden)
                    }
                }
            }
            .task(id: game.screen == .result ? (wide ? 2 : 1) : 0) {
                guard game.screen == .result else { return }
                // Let the inserted card participate in layout before locating
                // its bottom edge. Reapply if the result changes orientation.
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration:0.35)) {
                    scroll.scrollTo("game.result.card",anchor:.bottom)
                }
            }
        }
    }
    private var scoreboard: some View {
        VStack(spacing:16) {
            HStack {
                playerScore(name:game.name,score:game.ownScore,color:mint,icon:"person.fill")
                Spacer()
                VStack(spacing:5) {
                    Text(game.training ? L("menu.training") : L("native.duel")).font(.caption2.weight(.heavy)).tracking(2).foregroundStyle(muted)
                    Text("\(game.displayRound) / 30").font(.headline.monospacedDigit())
                }
                Spacer()
                playerScore(name:game.peerName.isEmpty ? L("player.opponent") : game.peerName,score:game.opponentScore,color:coral,icon:game.training ? "sparkles" : "person.fill")
            }
            .accessibilityElement(children:.combine)
            .accessibilityLabel("\(game.roundLabel). \(game.name): \(game.ownScore). \(game.peerName): \(game.opponentScore)")
            if game.screen == .game { RoundClock(game:game) }
        }.padding(.vertical,8)
    }
    private func playerScore(name: String, score: Int, color: Color, icon: String) -> some View {
        VStack(spacing:5) {
            HStack(spacing:8) { Image(systemName:icon).font(.caption); Text("\(score)").font(.system(size:32,weight:.heavy)).monospacedDigit() }.foregroundStyle(color)
            Text(name).font(.caption.weight(.medium)).lineLimit(1).frame(maxWidth:130)
        }
    }
    private var boardView: some View {
        BoardSceneView(scene:game.boardScene)
            .aspectRatio(720/828,contentMode:.fit)
            .clipShape(RoundedRectangle(cornerRadius:24))
            // Claim touches on the board before the surrounding ScrollView.
            .highPriorityGesture(DragGesture(minimumDistance:0)
                .updating($boardTouchActive) { _, active, _ in active = true }
                .onChanged { value in
                    game.boardScene.dragChanged(start:value.startLocation,location:value.location)
                }
                .onEnded { value in game.boardScene.dragEnded(at:value.location) })
            .onChange(of:boardTouchActive) { _, active in
                if !active {
                    Task { @MainActor in
                        // Let onEnded commit a normal release before handling cancellation.
                        await Task.yield()
                        if !boardTouchActive { game.boardScene.finishDrag(cancelled:true) }
                    }
                }
            }
            .accessibilityRepresentation {
                GeometryReader { geometry in
                    ForEach(0..<9) { p in
                        let frame=game.boardScene.accessibilityFrame(platform:p,size:geometry.size)
                        Color.clear.contentShape(Rectangle())
                            .accessibilityElement()
                            .accessibilityAction { game.chooseTurn(platform:p,direction:nil) }
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: game.chooseTurn(platform:p,direction:1)
                                case .decrement: game.chooseTurn(platform:p,direction:-1)
                                @unknown default: break
                                }
                            }
                            .frame(width:frame.width,height:frame.height)
                            .position(x:frame.midX,y:frame.midY)
                            .accessibilityLabel(platformDescription(p))
                            .accessibilityIdentifier("platform.\(p)")
                            .disabled(!game.active || game.paused)
                    }
                }
            }
    }
    private func platformDescription(_ p: Int) -> String {
        let r = p/3*2, c = p%3*2
        let tracks = [game.board.cells[r][c],game.board.cells[r][c+1],game.board.cells[r+1][c],game.board.cells[r+1][c+1]].map { mask in
            (0..<4).filter { mask & (1 << $0) != 0 }.map { L(["native.north","native.east","native.south","native.west"][$0]) }.joined(separator:"–")
        }.joined(separator:", ")
        let balls = game.board.balls.filter { Rules.platform($0.row,$0.col) == p }.count
        return "\(L("native.platform")) \(p+1). \(tracks). \(L("native.balls")): \(balls). \(game.board.cooldown.contains(p) ? L("error.platformCooldown") : "")"
    }
    private var turnControls: some View {
        VStack(spacing:14) {
            // Reserve the tallest localized hint at the current width and text size.
            // Changing the visible hint must not recenter the board above it.
            ZStack(alignment:.top) {
                Text(L("native.selectHint")).fixedSize(horizontal:false,vertical:true).hidden()
                Text(L("native.turnLimitHint")).fixedSize(horizontal:false,vertical:true).hidden()
                Text(L("native.selected")).fixedSize(horizontal:false,vertical:true).hidden()
            }
            .overlay(alignment:.top) {
                Text(game.turnLimitHint ? L("native.turnLimitHint") : game.selection == nil ? L("native.selectHint") : L("native.selected"))
                    .fixedSize(horizontal:false,vertical:true)
                    .foregroundStyle(game.turnLimitHint ? coral : game.selection == nil ? muted : mint)
            }
            .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
            if game.training {
                HStack {
                    Spacer()
                    Button { game.resolveTraining() } label: { Label(L("native.next"),systemImage:"forward.end.fill") }
                        .disabled(!game.active).accessibilityIdentifier("game.next")
                }.font(.subheadline.weight(.semibold)).frame(minHeight:44)
                Button(L("training.humanInvite")) { sheet = .setup("online") }.font(.caption)
                    .opacity(game.onlineCount % 2 == 1 ? 1 : 0)
                    .allowsHitTesting(game.onlineCount % 2 == 1)
                    .accessibilityHidden(game.onlineCount % 2 != 1)
            }
        }
    }
    private var resultCard: some View {
        VStack(spacing:16) {
            Image(systemName:game.ownScore > game.opponentScore ? "trophy.fill" : "flag.checkered").font(.largeTitle).foregroundStyle(LabTheme.amberInk)
            Text(game.resultTitle).font(.largeTitle.bold()).multilineTextAlignment(.center).accessibilityIdentifier("game.result")
            Text("\(game.ownScore) : \(game.opponentScore)").font(.title.monospacedDigit()).foregroundStyle(muted)
            if game.peerRematch { Text(L("native.rematchInvite")).font(.subheadline).foregroundStyle(mint) }
            Button { game.requestRematch() } label: {
                Text(L(game.rematchRequested ? "status.waitingOpponent" : "action.rematch")).frame(maxWidth:.infinity)
            }.buttonStyle(GameButtonStyle()).disabled(game.rematchRequested).accessibilityIdentifier("game.rematch")
            Button(L("action.newGame")) { game.leave() }.frame(minHeight:44).accessibilityIdentifier("game.newGame")
        }.padding(24).background(LabTheme.peach,in:RoundedRectangle(cornerRadius:28))
            .id("game.result.card")
    }
    private func setup(mode: String) -> some View {
        Form {
            Section {
                TextField(L("name.label"),text:$game.name).textContentType(.nickname).autocorrectionDisabled()
                    .onChange(of:game.name) { _,value in game.name = String(value.prefix(24)) }.accessibilityIdentifier("setup.name")
            } header: { Text(L("name.label")) }
            if mode == "training" {
                Section(L("name.difficulty")) {
                    VStack(spacing:12) {
                        HStack(spacing:6) {
                            ForEach(Difficulty.allCases,id:\.self) { level in
                                Button { game.difficulty = level } label: {
                                    Image("Difficulty" + level.rawValue.capitalized)
                                        .resizable().scaledToFit()
                                        .frame(height:level == .medium ? 90 : 104)
                                        .frame(height:104,alignment:.bottom)
                                        .frame(maxWidth:.infinity)
                                        .padding(.vertical,4)
                                        .background(game.difficulty == level ? LabTheme.mint : Color.clear,in:RoundedRectangle(cornerRadius:18))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("name.\(level.rawValue)"))
                                .accessibilityAddTraits(game.difficulty == level ? .isSelected : [])
                                .accessibilityIdentifier("setup.difficulty.\(level.rawValue)")
                            }
                        }
                        Picker(L("name.difficulty"),selection:$game.difficulty) {
                            ForEach(Difficulty.allCases,id:\.self) { Text(L("name.\($0.rawValue)")).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("setup.difficulty")
                    }
                }
            }
            if mode == "join" {
                Section {
                    InvitationCodeField(code:$code,invalid:$invalidJoinCode)
                } header: { Text(L("native.inviteCode")) }
                footer: {
                    if invalidJoinCode {
                        Text(L("native.invalidCode")).foregroundStyle(coral).accessibilityIdentifier("setup.code.error")
                    }
                }
            }
            Section {
                Button {
                    let roomCode = mode == "join" ? GameModel.roomCode(code) : nil
                    if mode == "join", roomCode == nil {
                        invalidJoinCode = true
                        return
                    }
                    guard game.rememberName() else { return }
                    if let roomCode {
                        game.startOnline("join",code:roomCode)
                    } else if mode == "training" { game.startTraining() }
                    else { game.startOnline(mode) }
                    sheet = nil
                } label: {
                    Label(L(mode == "training" ? "dialog.trainingSubmit" : mode == "host" ? "dialog.createSubmit" : mode == "join" ? "dialog.joinSubmit" : "dialog.onlineSubmit"),systemImage:mode == "training" ? "play.fill" : "arrow.right")
                        .frame(maxWidth:.infinity)
                }
                .buttonStyle(GameButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top:6,leading:0,bottom:6,trailing:0))
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("setup.start")
            } footer: {
                if mode != "training" {
                    Text(L("native.onlinePrivacy"))
                }
            }
        }.navigationTitle(L(mode == "training" ? "dialog.trainingTitle" : mode == "host" ? "dialog.createTitle" : mode == "join" ? "dialog.joinTitle" : "dialog.onlineTitle"))
            .onAppear { invalidJoinCode = false }
    }
    private var settings: some View {
        Form {
            Section {
                Toggle(L("sound.label"),isOn:Binding(get:{AudioEngine.shared.enabled},set:{AudioEngine.shared.enabled=$0})).accessibilityIdentifier("settings.sound")
                Toggle(L("lab.voices"),isOn:Binding(get:{AudioEngine.shared.voices},set:{AudioEngine.shared.voices=$0})).accessibilityIdentifier("settings.voices")
                Toggle(L("native.haptics"),isOn:Binding(get:{AudioEngine.shared.haptics},set:{AudioEngine.shared.haptics=$0}))
            }
            Section {
                Button(L("menu.how")) { sheet = .rules }
                Button(L("native.privacy")) { sheet = .privacy }
                Link(L("native.support"),destination:URL(string:"https://twivvy.e-notix.com/support.html")!)
                Button(L("native.language")) { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section {
                Text("\(L("meta.title")) \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") · © 2026 Dzmitry Sharko")
                    .font(.caption).foregroundStyle(muted)
            }
        }.navigationTitle(L("native.settings"))
    }
    private var rules: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                ForEach(Array([("rotate.3d","rules.board"),("circle.bottomhalf.filled","rules.goal"),("arrow.trianglehead.2.clockwise.rotate.90","rules.turn"),("sparkles","rules.spawn"),("eye.slash","rules.combine"),("lock.fill","rules.cooldown"),("flag.checkered","native.winRule"),("hand.draw.fill","native.gestureRule")].enumerated()),id:\.offset) { _, rule in
                    HStack(alignment:.top,spacing:18) {
                        Image(systemName:rule.0).font(.title2).foregroundStyle(mint).frame(width:32)
                        Text(L(rule.1)).fixedSize(horizontal:false,vertical:true)
                    }
                }
            }.padding(28)
        }.navigationTitle(L("menu.how"))
    }
    private var privacy: some View {
        ScrollView { Text(L("native.privacyText")).frame(maxWidth:.infinity,alignment:.leading).padding(28).textSelection(.enabled) }
            .navigationTitle(L("native.privacy"))
    }
}

private struct BoardSceneView: UIViewRepresentable {
    let scene: BoardScene
    func makeUIView(context: Context) -> LabSceneHost { LabSceneHost(scene:scene) }
    func updateUIView(_ host: LabSceneHost, context: Context) { host.scene=scene }
    static func dismantleUIView(_ host: LabSceneHost, coordinator: ()) { host.scene.pauseRenderer(from:host) }
}

/// Observe the 10 Hz countdown here, so a clock tick doesn't rebuild the board's
/// SwiftUI host, projected accessibility frames, menu and all game controls.
private struct RoundClock: View {
    let game: GameModel
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment:.leading) {
                Capsule().fill(LabTheme.mint)
                Capsule().fill(game.remaining < 5 ? coral : mint)
                    .frame(width:proxy.size.width * min(1,max(0,game.remaining/30)))
            }
        }.frame(height:4)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(game.paused ? L("native.recovering") : game.active ? L("native.yourMove") : L("status.waitingOpponent"))
            .accessibilityValue(Text(min(1,max(0,game.remaining/30)),format:.percent.precision(.fractionLength(0))))
    }
}

/// Reparent the same renderer across compact/wide SwiftUI layout changes.
final class LabSceneHost: UIView {
    var scene: BoardScene {
        didSet {
            if oldValue !== scene { oldValue.pauseRenderer(from:self) }
            adopt()
        }
    }
    init(scene: BoardScene) {
        self.scene=scene; super.init(frame:.zero)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("Use init(scene:)") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { adopt() }
        else { scene.pauseRenderer(from:self) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout callbacks can arrive after removal. Never create a renderer
        // here: only adopt() may create one for a host that is in a window.
        if let renderer=scene.view,renderer.superview === self { renderer.frame=bounds }
    }
    private func adopt() {
        guard window != nil else { return }
        let renderer=scene.rendererView()
        if renderer.superview !== self { addSubview(renderer) }
        renderer.frame=bounds
    }
}

private struct InvitationCodeField: View {
    @Binding var code: String
    @Binding var invalid: Bool
    @FocusState private var focused: Bool

    var body: some View {
        TextField(L("native.codeHint"),text:$code)
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .focused($focused)
            .padding(10)
            .background(invalid ? coral.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:8))
            .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(invalid ? coral : .clear,lineWidth:2) }
            .onChange(of:code) { _,_ in invalid = false }
            .task(id:invalid) {
                if invalid {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    focused = true
                }
            }
            .accessibilityHint(invalid ? L("native.invalidCode") : "")
            .accessibilityIdentifier("setup.code")
    }
}

struct GameButtonStyle: ButtonStyle {
    var secondary = false
    var playful = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.bold)).padding(.horizontal,18).padding(.vertical,18)
            .frame(minHeight:56)
            .foregroundStyle(secondary ? LabTheme.teal : LabTheme.ink)
            .background {
                RoundedRectangle(cornerRadius:18).fill(secondary ? playful ? LabTheme.peach : LabTheme.mint : LabTheme.sunshine)
            }
            .overlay { RoundedRectangle(cornerRadius:18).strokeBorder(secondary ? LabTheme.border : LabTheme.amberInk.opacity(0.20),lineWidth:1) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}
