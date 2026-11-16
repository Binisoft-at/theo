import SwiftUI
import SwiftData
import Combine

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue
    @AppStorage(Prefs.textSize) private var textSizeRaw = TextSizeChoice.platformDefault.rawValue
    /// The toolbar search field (Mac and iPad), focused by Find… (⌘F).
    @FocusState private var searchFocused: Bool

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var appearance: AppearanceChoice { AppearanceChoice(rawValue: appearanceRaw) ?? .system }
    private var accent: AccentChoice { AccentChoice(rawValue: accentRaw) ?? .notes }

    /// iPhone gets a tab bar (Today, Plan, Lists, Search); iPad and Mac get a split view.
    @ViewBuilder
    private var navigation: some View {
        #if os(iOS)
        if sizeClass == .compact {
            phoneTabs
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    #if os(iOS)
    private var phoneTabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.phoneTab) {
            Tab("Today", systemImage: "sun.max.fill", value: PhoneTab.today) {
                NavigationStack {
                    TodayView(dayStart: app.dayStart)
                        .navigationDestination(for: DayRef.self) { day in
                            DayPageView(day: day)
                        }
                }
            }
            Tab("Plan", systemImage: "calendar.badge.plus", value: PhoneTab.plan) {
                NavigationStack {
                    PlanView()
                }
            }
            Tab("Overview", systemImage: "chart.pie", value: PhoneTab.overview) {
                NavigationStack {
                    OverviewView()
                        // Back from a page pushed here: the Overview is in front again.
                        .onAppear { if app.phoneTab == .overview { app.selection = .overview } }
                        .navigationDestination(for: SidebarItem.self) { item in
                            DetailRouter(selection: item, dayStart: app.dayStart)
                                .onAppear { app.selection = item }
                        }
                        // History (pushed from "done in 7 days") opens its days in place.
                        .navigationDestination(for: DayRef.self) { day in
                            DayPageView(day: day)
                        }
                }
            }
            Tab("Lists", systemImage: "list.bullet", value: PhoneTab.lists) {
                NavigationStack(path: $app.phonePath) {
                    SidebarView(usesSelection: false, showsDayPages: false)
                        .navigationDestination(for: SidebarItem.self) { item in
                            DetailRouter(selection: item, dayStart: app.dayStart)
                                .onAppear { app.selection = item }
                        }
                        .navigationDestination(for: DayRef.self) { day in
                            DayPageView(day: day)
                        }
                }
            }
            Tab(value: PhoneTab.search, role: .search) {
                NavigationStack {
                    SearchPage()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: app.phoneTab) { _, tab in
            // `selection` follows the page in front, so the Home Screen's New Task adds there
            // (Plan's bar plans for its day) and never jumps to a tab you've left.
            switch tab {
            case .today: app.selection = .today
            case .plan: app.selection = .plan
            case .overview: app.selection = .overview
            case .lists: if app.phonePath.isEmpty { app.selection = nil }
            case .search: app.selection = nil
            }
        }
    }
    #endif

    private var splitView: some View {
        @Bindable var app = app
        return NavigationSplitView(preferredCompactColumn: $app.compactColumn) {
            SidebarView(usesSelection: true)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            NavigationStack(path: $app.detailPath) {
                DetailRouter(selection: app.selection, dayStart: app.dayStart, search: app.searchText)
                    .navigationDestination(for: DayRef.self) { day in
                        DayPageView(day: day)
                    }
            }
            // One search over every task, from any page (Find…, ⌘F). Esc or a page change clears it.
            .searchable(text: $app.searchText, placement: .toolbar, prompt: "Search all tasks")
            .searchFocused($searchFocused)
            #if os(macOS)
            // The space a wide window has to spare goes to the selected task's details.
            .inspector(isPresented: $app.showInspector) {
                TaskInspector()
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        app.showInspector.toggle()
                    } label: {
                        Label(app.showInspector ? "Hide Details" : "Show Details", systemImage: "sidebar.trailing")
                    }
                    .help("Details of the selected task (⌥⌘I)")
                }
            }
            .onChange(of: app.showInspector) { _, shown in
                UserDefaults.standard.set(shown, forKey: "inspector.shown")
            }
            #endif
        }
    }

    var body: some View {
        @Bindable var app = app
        navigation
        // Red when Theo couldn't open its storage, orange when it isn't syncing; nothing otherwise.
        .safeAreaInset(edge: .top, spacing: 0) {
            StorageWarningBanner()
        }
        .theoTextSize(TextSizeChoice(rawValue: textSizeRaw) ?? .platformDefault)
        .tint(accent.color)
        .preferredColorScheme(appearance.colorScheme)
        .modifier(AppChrome(app: app, accent: accent.color))
        #if os(iOS)
        .sheet(isPresented: $app.showSettings) {
            NavigationStack {
                SettingsView()
            }
            .tint(accent.color)
        }
        .fullScreenCover(item: $app.tour) { request in
            TutorialView(steps: request.steps) { app.finishTour() }
                .preferredColorScheme(appearance.colorScheme)
        }
        #else
        .sheet(item: $app.tour) { request in
            TutorialView(steps: request.steps) { app.finishTour() }
                .frame(minWidth: 760, idealWidth: 900, minHeight: 600, idealHeight: 780)
        }
        #endif
        .onAppear {
            // Shake to undo / ⌘Z for every change, not just text.
            app.container.mainContext.undoManager = undoManager
            // A Find… from while no window was open would otherwise stay set, and the next ⌘F
            // would change nothing.
            app.wantsSearchFocus = false
        }
        .onChange(of: undoManager) { _, manager in
            app.container.mainContext.undoManager = manager
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            app.offerTourIfNeeded()
            // The daily backup at launch (a scene's first phase sends no change).
            app.backups.backUpIfDue()
        }
        .onReceive(clock) { _ in
            // A Mac window stays "active" for days: the new day, a focus phase that ran out and
            // the daily backup are checked here too (each is a cheap check when nothing is due).
            app.refreshDay()
            app.tickFocus()
            app.backups.backUpIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            // Hand changes to iCloud before the app goes to sleep.
            if phase != .active { app.store.save() }
            if phase == .active {
                app.backups.backUpIfDue()
                app.refreshDay()
                app.tickFocus()
                app.reminders?.scheduleSoon()
                if QuickActions.pendingQuickEntry {
                    QuickActions.pendingQuickEntry = false
                    app.requestQuickEntry()
                }
            }
        }
        .onChange(of: app.selection) { _, _ in
            // A page change clears the old page's selection, unless `reveal(_:)` asked for a row.
            app.selectedRowIDs = app.pendingRevealRowID.map { Set([$0]) } ?? []
            app.pendingRevealRowID = nil
            app.isSelecting = false
            app.searchText = ""
        }
        .onChange(of: app.searchText) { _, text in
            // The results replace the page at the bottom of the stack: a day opened on top of it
            // (History) would hide them.
            if !text.isEmpty && !app.detailPath.isEmpty { app.detailPath = NavigationPath() }
        }
        .onChange(of: app.wantsSearchFocus) { _, wants in
            guard wants else { return }
            app.wantsSearchFocus = false
            #if os(iOS)
            // The iPhone searches in its Search tab.
            if sizeClass == .compact {
                app.phoneTab = .search
                return
            }
            #endif
            searchFocused = true
        }
    }
}

/// Toasts and the sheets any page can open. Shared by the app window and the tour's practice page.
struct AppChrome: ViewModifier {
    @Bindable var app: AppModel
    let accent: Color

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = app.toast {
                    ToastView(toast: toast) {
                        withAnimation(.snappy) { app.toast = nil }
                    }
                    .tint(toast.isWarning ? Color.red : accent)
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $app.detailTask) { task in
                TaskDetailView(task: task)
                    .tint(accent)
            }
            .sheet(item: $app.moveBatch) { batch in
                MoveSheet(batch: batch)
                    .tint(accent)
            }
            .sheet(item: $app.dateBatch) { batch in
                DateSheet(batch: batch)
                    .tint(accent)
            }
            .sheet(item: $app.tagBatch) { batch in
                TagSheet(batch: batch)
                    .tint(accent)
            }
            .sheet(item: $app.groupEditor) { target in
                GroupEditorView(target: target)
                    .tint(accent)
            }
            .sheet(isPresented: $app.showImport) {
                ImportView()
                    .tint(accent)
            }
            .sheet(isPresented: $app.showFocus) {
                FocusView()
                    .tint(accent)
            }
            .sheet(item: $app.reviewDay) { day in
                NavigationStack {
                    DayReviewView(day: day.start)
                }
                .tint(accent)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 620)
                #endif
            }
            .overlay {
                if let drag = app.matrixDrag {
                    MatrixDropOverlay(drag: drag)
                        .tint(accent)
                } else if let task = app.matrixTask {
                    MatrixPlacementOverlay(task: task)
                        .tint(accent)
                }
            }
            .overlay {
                if let location = app.insertDragLocation {
                    InsertGhost(title: app.insertDragTitle, location: location)
                        .tint(accent)
                }
            }
            .overlay {
                if let pick = app.radialPick {
                    RadialPickerOverlay(pick: pick)
                        .tint(accent)
                }
            }
            .overlay {
                // Measures the visible part of the window (it shrinks above the keyboard), so a
                // circular pick always opens where it can be seen.
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { app.visibleFrame = $0 }
                    .allowsHitTesting(false)
            }
            .animation(.snappy(duration: 0.16), value: app.radialPick?.id)
            .animation(.snappy(duration: 0.2), value: app.matrixDrag == nil)
            .animation(.snappy(duration: 0.2), value: app.matrixTask == nil)
    }
}

/// The task the composer's + carries while it's dragged over a list, just above the finger.
struct InsertGhost: View {
    let title: String
    /// Finger position in global coordinates.
    let location: CGPoint

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            Label(title.isEmpty ? "New Task" : title, systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: 240)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.25)), in: .capsule)
                .fixedSize()
                .position(x: location.x - origin.x + 60, y: location.y - origin.y - 34)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

/// Picks the page for the current sidebar selection.
struct DetailRouter: View {
    let selection: SidebarItem?
    let dayStart: Date
    /// The toolbar search (Mac and iPad): while it holds text, the results replace the page.
    var search = ""

    var body: some View {
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            page
        } else {
            // A task list like any page: selection, the details column and right-click work.
            SearchResultsView(query: search)
                .navigationTitle("Search")
        }
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .today, .none:
            TodayView(dayStart: dayStart)
        case .plan:
            PlanView()
        case .overview:
            OverviewView()
        case .allTasks:
            AllTasksView()
        case .view(let id):
            AllTasksView(viewID: id)
                .id(id)
        case .upcoming:
            UpcomingView()
        case .priority:
            PriorityView()
        case .matrix:
            MatrixPageView()
        case .quickEntry:
            GroupPageView(groupID: nil)
        case .group(let id):
            GroupPageView(groupID: id)
                .id(id)
        case .tag(let tag):
            TagView(tag: tag)
                .id(tag)
        case .history:
            HistoryView()
        case .trash:
            TrashView()
        }
    }
}

/// The Search tab: everything, including History.
struct SearchPage: View {
    @State private var query = ""

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search Theo", systemImage: "magnifyingglass", description: Text("Titles, notes and tags, including finished tasks."))
            } else {
                SearchResultsView(query: query)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search all tasks")
    }
}

/// Bridges UIKit-only entry points (Home Screen quick actions) into SwiftUI.
enum QuickActions {
    nonisolated(unsafe) static var pendingQuickEntry = false
}
