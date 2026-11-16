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
                        // The column slides in and out instead of appearing at once.
                        Motion.animate(Motion.layout) { app.showInspector.toggle() }
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
        .tint(accent.color)
        .preferredColorScheme(appearance.colorScheme)
        .modifier(AppChrome(app: app, accent: accent.color))
        // Outside the toasts and sheets, so they follow the text size too.
        .theoTextSize(TextSizeChoice(rawValue: textSizeRaw) ?? .platformDefault)
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
                .theoStoredTextSize()
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
        // Links from the widgets and Control Center (theo://today, theo://task/<id>,
        // theo://quick-entry). This window takes them instead of opening another one.
        .onOpenURL { url in
            app.openLink(url)
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
}

/// Toasts and the sheets any page can open. Shared by the app window and the tour's practice page.
struct AppChrome: ViewModifier {
    @Bindable var app: AppModel
    let accent: Color

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                toastLayer
            }
            .sheet(item: $app.detailTask) { task in
                TaskDetailView(task: task)
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(item: $app.moveBatch) { batch in
                MoveSheet(batch: batch)
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(item: $app.dateBatch) { batch in
                DateSheet(batch: batch)
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(item: $app.tagBatch) { batch in
                TagSheet(batch: batch)
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(item: $app.groupEditor) { target in
                GroupEditorView(target: target)
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(isPresented: $app.showImport) {
                ImportView()
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(isPresented: $app.showFocus) {
                FocusView()
                    .tint(accent)
                    .theoStoredTextSize()
            }
            .sheet(item: $app.reviewDay) { day in
                NavigationStack {
                    DayReviewView(day: day.start)
                }
                .tint(accent)
                .theoStoredTextSize()
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
                insertGhostLayer
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
            // The arc and the canvas follow a finger: quick. A task placed on the grid from a
            // menu opens and closes like any panel.
            .animation(Motion.resolved(Motion.tap), value: app.radialPick?.id)
            .animation(Motion.resolved(Motion.tap), value: app.matrixDrag == nil)
            .animation(Motion.resolved(Motion.layout), value: app.matrixTask == nil)
    }

    /// The toast rises from just below the bottom bar with a little spring and settles there;
    /// a newer one takes its place the same way while the old one sinks and fades under it.
    /// Leaving, it sinks back the way it came, a little quicker.
    @MainActor
    private var toastLayer: some View {
        ZStack {
            if let toast = app.toast {
                LandingToast(toast: toast) {
                    Motion.animate(Motion.tap) { app.toast = nil }
                }
                .tint(toast.isWarning ? Color.red : accent)
                .id(toast.id)
                .transition(Self.toastTransition)
            }
        }
        .padding(.bottom, 84)
        .animation(toastAnimation, value: app.toast?.id)
    }

    /// A confirmation springs in; a warning comes in smoothly, without the playfulness; going
    /// away is quick.
    @MainActor
    private var toastAnimation: Animation {
        guard let toast = app.toast else { return Motion.resolved(Motion.tap) }
        return Motion.resolved(toast.isWarning ? Motion.layout : Motion.celebrate)
    }

    /// In: up from a little below, growing from its bottom edge, fading in. Out: a shorter way
    /// down, fading. With Reduce Motion it only fades.
    @MainActor
    private static var toastTransition: AnyTransition {
        guard !Motion.reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 32).combined(with: .scale(scale: 0.9, anchor: .bottom)).combined(with: .opacity),
            removal: .offset(y: 16).combined(with: .scale(scale: 0.96, anchor: .bottom)).combined(with: .opacity)
        )
    }

    /// The composer's + while it's dragged over a list: it fades in under the finger and out
    /// where it's let go. Only its coming and going animate; it follows the finger as is.
    @MainActor
    private var insertGhostLayer: some View {
        ZStack {
            if let location = app.insertDragLocation {
                InsertGhost(title: app.insertDragTitle, location: location, accent: accent)
                    .tint(accent)
            }
        }
        .animation(Motion.resolved(Motion.tap), value: app.insertDragLocation == nil)
    }
}

/// A toast that, once it has risen into place, gives its symbol one small bounce: the
/// confirmation lands with it. Warnings don't bounce.
private struct LandingToast: View {
    let toast: Toast
    let dismiss: () -> Void

    @State private var landed = false

    var body: some View {
        ToastView(toast: toast, dismiss: dismiss)
            .symbolEffect(.bounce, value: landed)
            .task {
                // After the spring has carried it up, not while it's still rising.
                try? await Task.sleep(for: .milliseconds(180))
                if !toast.isWarning && !Motion.reduceMotion { landed = true }
            }
    }
}

/// The task the composer's + carries while it's dragged over a list, just above the finger:
/// lifted off the page, with the + it came from.
struct InsertGhost: View {
    let title: String
    /// Finger position in global coordinates.
    let location: CGPoint
    /// The chosen accent (the glass takes a colour, not the tint).
    var accent: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            Label {
                Text(title.isEmpty ? "New Task" : title)
            } icon: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
            }
            .theoFont(.subheadline, weight: .semibold)
            .lineLimit(1)
            .frame(maxWidth: 240)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(accent.opacity(0.25)), in: .capsule)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
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
