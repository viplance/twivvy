import SwiftUI
import SpriteKit

private let mint = Color(red:0.40,green:0.94,blue:0.81)
private let coral = Color(red:1,green:0.60,blue:0.71)
private let muted = Color(red:0.63,green:0.70,blue:0.82)

struct ContentView: View {
    @Bindable var game: GameModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: Panel?
    @State private var pendingMode = "training"
    @State private var code = ""
    @State private var confirmLeave = false
    @State private var incomingCode: String?
    enum Panel: String, Identifiable { case setup, settings, rules, privacy; var id: String { rawValue } }
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
        .fontDesign(.rounded)
        .tint(mint)
        .sheet(item:$sheet) { panel in
            NavigationStack {
                Group {
                    switch panel {
                    case .setup: setup
                    case .settings: settings
                    case .rules: rules
                    case .privacy: privacy
                    }
                }
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button(L("native.done")) { sheet = nil }.accessibilityIdentifier("sheet.done") } }
                .toolbarBackground(Color(red:0.06,green:0.10,blue:0.19),for:.navigationBar)
            }.presentationDetents([.large]).preferredColorScheme(.dark)
        }
        .alert(L("native.notice"),isPresented:Binding(get:{game.error != nil},set:{if !$0 {game.error=nil}})) {
            Button(L("native.done"),role:.cancel) { game.error = nil }
        } message: { Text(game.error ?? "") }
        .confirmationDialog(L("native.leaveQuestion"),isPresented:$confirmLeave,titleVisibility:.visible) {
            Button(L("native.leave"),role:.destructive) {
                game.leave()
                if let incomingCode { code = incomingCode; self.incomingCode = nil; pendingMode = "join"; sheet = .setup }
            }
            Button(L("action.cancel"),role:.cancel) { incomingCode = nil }
        }
        .onChange(of:scenePhase) { _, phase in
            if phase == .active { game.foreground() }
            else if phase == .background { game.background() }
        }
        .onOpenURL { acceptInvitation($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { acceptInvitation(url) }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                game.name = "Explorer"
                AudioEngine.shared.enabled = false
                if ProcessInfo.processInfo.arguments.contains("--training") { game.startTraining() }
            }
        }
    }
    private func acceptInvitation(_ url: URL) {
        guard let value = game.handleURL(url) else { return }
        if game.screen == .menu { code = value; pendingMode = "join"; sheet = .setup }
        else { incomingCode = value; confirmLeave = true }
    }
    private var background: some View {
        ZStack {
            Color(red:0.035,green:0.060,blue:0.12)
            RadialGradient(colors:[Color(red:0.12,green:0.22,blue:0.34).opacity(0.8),.clear],center:.topLeading,startRadius:10,endRadius:650)
            RadialGradient(colors:[Color.purple.opacity(0.11),.clear],center:.bottomTrailing,startRadius:10,endRadius:500)
        }.ignoresSafeArea()
    }
    private var topBar: some View {
        HStack {
            if game.screen != .menu {
                Button { confirmLeave = true } label: { Image(systemName:"chevron.left").frame(width:44,height:44) }
                    .accessibilityLabel(L("native.leave")).accessibilityIdentifier("game.leave")
            } else {
                HStack(spacing:7) { Image(systemName:"circle.hexagongrid.fill").foregroundStyle(mint); Text("TWIVVY").tracking(3).font(.caption.weight(.heavy)) }
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
                    menuArt.frame(height:min(size.height*0.32,310))
                    menuActions
                }.padding(.horizontal,28).padding(.top,12).padding(.bottom,24).frame(maxWidth:560).frame(maxWidth:.infinity)
            }
        }.scrollIndicators(.hidden)
    }
    private var title: some View {
        VStack(spacing:12) {
            Text(L("native.eyebrow")).font(.caption.weight(.bold)).tracking(3).foregroundStyle(mint)
            Text(L("meta.title")).font(.system(size:62,weight:.black,design:.rounded)).tracking(-3)
                .foregroundStyle(LinearGradient(colors:[.white,Color(red:0.65,green:0.85,blue:0.98)],startPoint:.top,endPoint:.bottom))
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(L("tagline.first")+"\n"+L("tagline.second"))
                .font(.subheadline).foregroundStyle(muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var menuIntro: some View { VStack(spacing:30) { title; menuActions }.frame(maxWidth:420) }
    private var menuArt: some View {
        ZStack {
            Circle().fill(mint.opacity(0.06)).blur(radius:30).padding(25)
            SpriteView(scene:game.boardScene,options:[.allowsTransparency])
                .aspectRatio(720/828,contentMode:.fit).rotationEffect(.degrees(-7))
                .shadow(color:mint.opacity(0.10),radius:30).allowsHitTesting(false)
        }.accessibilityHidden(true)
    }
    private var menuActions: some View {
        VStack(spacing:12) {
            Button { pendingMode = "online"; sheet = .setup } label: {
                HStack { Image(systemName:"globe.europe.africa.fill"); Text(L("menu.online")); Spacer(); Image(systemName:"arrow.right") }
            }.buttonStyle(GameButtonStyle()).accessibilityIdentifier("menu.online")
            HStack(spacing:12) {
                Button { pendingMode = "host"; sheet = .setup } label: {
                    Label(L("menu.friend"),systemImage:"person.2.fill").frame(maxWidth:.infinity)
                }.buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("menu.friend")
                Button { pendingMode = "training"; sheet = .setup } label: {
                    Label(L("menu.training"),systemImage:"sparkles").frame(maxWidth:.infinity)
                }.buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("menu.training")
            }
            Button { pendingMode = "join"; sheet = .setup } label: {
                Label(L("native.haveCode"),systemImage:"link").font(.subheadline.weight(.semibold)).padding(10)
            }.accessibilityIdentifier("menu.join")
            if game.hasSavedGame {
                Button { game.resume() } label: { Label(L("native.resume"),systemImage:"arrow.clockwise").frame(maxWidth:.infinity) }
                    .buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("menu.resume")
            }
            HStack(spacing:7) { Circle().fill(mint).frame(width:5,height:5); Text(L("native.footer")) }
                .font(.caption2).foregroundStyle(muted).padding(.top,6)
        }
    }
    private var lobby: some View {
        ScrollView {
            VStack(spacing:28) {
                Image(systemName:game.roomCode.isEmpty ? "globe.europe.africa" : "person.2.wave.2.fill")
                    .font(.system(size:70)).foregroundStyle(mint).padding(.top,60)
                Text(L(game.roomCode.isEmpty ? "status.finding" : "lobby.created")).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(game.status).foregroundStyle(muted).multilineTextAlignment(.center)
                ProgressView().tint(mint)
                if !game.roomCode.isEmpty {
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
    @ViewBuilder private func arena(wide: Bool, size: CGSize) -> some View {
        if wide {
            HStack(spacing:24) {
                boardView.frame(maxWidth:.infinity,maxHeight:.infinity)
                ScrollView { VStack(spacing:22) { scoreboard; turnControls; if game.screen == .result { resultCard } }.padding(20) }.frame(width:320)
            }.padding(.horizontal,24).padding(.bottom,16)
        } else {
            ScrollView {
                VStack(spacing:12) {
                    scoreboard.padding(.horizontal,24)
                    boardView.frame(height:min(max(size.height*0.46,260),600))
                    if game.screen == .result { resultCard.padding(.horizontal,24) }
                    else { turnControls.padding(.horizontal,24) }
                }.padding(.bottom,24).frame(maxWidth:700).frame(maxWidth:.infinity)
            }.scrollIndicators(.hidden)
        }
    }
    private var scoreboard: some View {
        VStack(spacing:16) {
            HStack {
                playerScore(name:game.name,score:game.ownScore,color:mint,icon:"person.fill")
                Spacer()
                VStack(spacing:5) {
                    Text(game.training ? L("menu.training") : "DUEL").font(.caption2.weight(.heavy)).tracking(2).foregroundStyle(muted)
                    Text("\(game.displayRound) / 30").font(.headline.monospacedDigit())
                }
                Spacer()
                playerScore(name:game.peerName.isEmpty ? L("player.opponent") : game.peerName,score:game.opponentScore,color:coral,icon:game.training ? "sparkles" : "person.fill")
            }
            .accessibilityElement(children:.combine)
            .accessibilityLabel("\(game.roundLabel). \(game.name): \(game.ownScore). \(game.peerName): \(game.opponentScore)")
            if game.screen == .game {
                VStack(spacing:7) {
                    HStack {
                        Text(game.paused ? L("native.recovering") : game.active ? L("native.yourMove") : L("status.waitingOpponent"))
                        Spacer()
                        Text("\(Int(ceil(game.remaining)))s").monospacedDigit().foregroundStyle(game.remaining < 5 ? coral : mint)
                    }.font(.caption.weight(.semibold))
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(LinearGradient(colors:[mint,.cyan],startPoint:.leading,endPoint:.trailing))
                            .frame(width:proxy.size.width * min(1,max(0,game.remaining/30)))
                    }.frame(height:4)
                }.foregroundStyle(muted)
            }
        }.padding(.vertical,8)
    }
    private func playerScore(name: String, score: Int, color: Color, icon: String) -> some View {
        VStack(spacing:5) {
            HStack(spacing:8) { Image(systemName:icon).font(.caption); Text("\(score)").font(.system(size:32,weight:.heavy)).monospacedDigit() }.foregroundStyle(color)
            Text(name).font(.caption.weight(.medium)).lineLimit(1).frame(maxWidth:130)
        }
    }
    private var boardView: some View {
        SpriteView(scene:game.boardScene,options:[.allowsTransparency])
            .aspectRatio(720/828,contentMode:.fit)
            .accessibilityRepresentation {
                GeometryReader { geometry in
                    VStack(spacing:0) {
                        ForEach(0..<3) { row in
                            HStack(spacing:0) {
                                ForEach(0..<3) { col in
                                    let index = row*3+col
                                    let p = game.side == .bottom ? index : 8-index
                                    Button { game.select(p) } label: {
                                        Color.clear.contentShape(Rectangle())
                                    }
                                    .frame(width:geometry.size.width*0.3,height:geometry.size.height*216/828)
                                    .accessibilityLabel(platformDescription(p))
                                    .accessibilityIdentifier("platform.\(p)")
                                    .disabled(!game.active || game.board.cooldown.contains(p))
                                }
                            }
                        }
                    }
                    .padding(.horizontal,geometry.size.width*0.05)
                    .padding(.vertical,geometry.size.height*90/828)
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
            Text(game.selection == nil ? L("native.selectHint") : LF("native.selected",["platform":"\(game.selection!.platform+1)"]))
                .font(.subheadline.weight(.medium)).foregroundStyle(game.selection == nil ? muted : mint).multilineTextAlignment(.center)
            HStack(spacing:12) {
                Button { game.rotate(-1) } label: { Label(L("native.left"),systemImage:"arrow.counterclockwise").frame(maxWidth:.infinity) }
                    .buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("game.ccw")
                Button { game.rotate(1) } label: { Label(L("native.right"),systemImage:"arrow.clockwise").frame(maxWidth:.infinity) }
                    .buttonStyle(GameButtonStyle(secondary:true)).accessibilityIdentifier("game.cw")
            }.disabled(!game.active || game.selectedPlatform == nil || game.paused)
            HStack {
                Button(L("native.skip")) { game.skip() }.disabled(!game.active).accessibilityIdentifier("game.skip")
                Spacer()
                if game.training {
                    Button { game.resolveTraining() } label: { Label(L("native.next"),systemImage:"forward.end.fill") }
                        .disabled(!game.active).accessibilityIdentifier("game.next")
                } else { Label(L("native.hidden"),systemImage:"lock.fill").font(.caption).foregroundStyle(muted) }
            }.font(.subheadline.weight(.semibold)).frame(minHeight:44)
            if game.training && game.onlineCount % 2 == 1 {
                Button(L("training.humanInvite")) { pendingMode = "online"; sheet = .setup }.font(.caption)
            }
        }
    }
    private var resultCard: some View {
        VStack(spacing:16) {
            Image(systemName:game.ownScore > game.opponentScore ? "trophy.fill" : "flag.checkered").font(.largeTitle).foregroundStyle(Color.yellow)
            Text(game.resultTitle).font(.largeTitle.bold()).multilineTextAlignment(.center).accessibilityIdentifier("game.result")
            Text("\(game.ownScore) : \(game.opponentScore)").font(.title.monospacedDigit()).foregroundStyle(muted)
            if game.peerRematch { Text(L("native.rematchInvite")).font(.subheadline).foregroundStyle(mint) }
            Button { game.requestRematch() } label: {
                Text(L(game.rematchRequested ? "status.waitingOpponent" : "action.rematch")).frame(maxWidth:.infinity)
            }.buttonStyle(GameButtonStyle()).disabled(game.rematchRequested).accessibilityIdentifier("game.rematch")
            Button(L("action.newGame")) { game.leave() }.frame(minHeight:44)
        }.padding(24).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:28))
    }
    private var setup: some View {
        Form {
            Section {
                TextField(L("name.label"),text:$game.name).textContentType(.nickname).autocorrectionDisabled()
                    .onChange(of:game.name) { _,value in game.name = String(value.prefix(24)) }.accessibilityIdentifier("setup.name")
            } header: { Text(L("name.label")) }
            if pendingMode == "training" {
                Section(L("name.difficulty")) {
                    Picker(L("name.difficulty"),selection:$game.difficulty) { ForEach(Difficulty.allCases,id:\.self) { Text(L("name.\($0.rawValue)")).tag($0) } }.pickerStyle(.segmented)
                }
            }
            if pendingMode == "join" {
                Section(L("native.inviteCode")) {
                    TextField(L("native.codeHint"),text:$code).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("setup.code")
                }
            }
            Section {
                Button {
                    guard game.rememberName() else { return }
                    if pendingMode == "join" {
                        guard let valid = GameModel.roomCode(code) else { game.error = L("native.invalidCode"); return }
                        game.startOnline("join",code:valid)
                    } else if pendingMode == "training" { game.startTraining() }
                    else { game.startOnline(pendingMode) }
                    sheet = nil
                } label: { Text(L(pendingMode == "training" ? "dialog.trainingSubmit" : pendingMode == "host" ? "dialog.createSubmit" : pendingMode == "join" ? "dialog.joinSubmit" : "dialog.onlineSubmit")).frame(maxWidth:.infinity).font(.headline).padding(8) }
                .accessibilityIdentifier("setup.start")
            } footer: {
                Text(L(pendingMode == "training" ? "native.offline" : "native.onlinePrivacy"))
            }
        }.navigationTitle(L(pendingMode == "training" ? "dialog.trainingTitle" : pendingMode == "host" ? "dialog.createTitle" : pendingMode == "join" ? "dialog.joinTitle" : "dialog.onlineTitle"))
    }
    private var settings: some View {
        Form {
            Section {
                Toggle(L("sound.label"),isOn:Binding(get:{AudioEngine.shared.enabled},set:{AudioEngine.shared.enabled=$0})).accessibilityIdentifier("settings.sound")
                Toggle(L("native.haptics"),isOn:Binding(get:{AudioEngine.shared.haptics},set:{AudioEngine.shared.haptics=$0}))
            }
            Section {
                Button(L("menu.how")) { sheet = .rules }
                Button(L("native.privacy")) { sheet = .privacy }
                Link(L("native.support"),destination:URL(string:"https://twivvy.e-notix.com/support.html")!)
                Button(L("native.language")) { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section { Text("Twivvy 1.0 · © 2026 Dzmitry Sharko").font(.caption).foregroundStyle(muted) }
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

struct GameButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.bold)).padding(.horizontal,18).padding(.vertical,18)
            .frame(minHeight:56)
            .foregroundStyle(secondary ? Color.white : Color(red:0.03,green:0.14,blue:0.15))
            .background {
                RoundedRectangle(cornerRadius:18).fill(secondary ? AnyShapeStyle(.white.opacity(0.06)) : AnyShapeStyle(LinearGradient(colors:[mint,Color(red:0.37,green:0.77,blue:0.95)],startPoint:.leading,endPoint:.trailing)))
            }
            .overlay { RoundedRectangle(cornerRadius:18).strokeBorder(.white.opacity(secondary ? 0.10 : 0.20),lineWidth:1) }
            .opacity(enabled ? configuration.isPressed ? 0.7 : 1 : 0.35)
    }
}
