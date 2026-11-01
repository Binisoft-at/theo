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

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var appearance: AppearanceChoice { AppearanceChoice(rawValue: appearanceRaw) ?? .system }
    private var accent: AccentChoice { AccentChoice(rawValue: accentRaw) ?? .notes }

    /// iPhone gets a single Notes-style stack (lists → page); iPad and Mac get a split view.
    @ViewBuilder
    private var navigation: some View {
        @Bindable var app = app
        #if os(iOS)
        if sizeClass == .compact {
            NavigationStack(path: $app.phonePath) {
                SidebarView(usesSelection: false)
                    .navigationDestination(for: SidebarItem.self) { item in
                        DetailRouter(selection: item, dayStart: app.dayStart)
                            .onAppear { app.selection = item }
                    }
                    .navigationDestination(for: DayRef.self) { day in
                        DayPageView(day: day)
                    }
            }
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    private var splitView: some View {
        @Bindable var app = app
        return NavigationSplitView(preferredCompactColumn: $app.compactColumn) {
            SidebarView(usesSelection: true)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            NavigationStack(path: $app.detailPath) {
                DetailRouter(selection: app.selection, dayStart: app.dayStart)
                    .navigationDestination(for: DayRef.self) { day in
                        DayPageView(day: day)
                    }
            }
        }
    }

    var body: some View {
        @Bindable var app = app
        navigation
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
        }
        .onChange(of: undoManager) { _, manager in
            app.container.mainContext.undoManager = manager
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            app.offerTourIfNeeded()
        }
        .onReceive(clock) { _ in
            app.refreshDay()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
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
            app.selectedRowIDs = []
            app.isSelecting = false
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
            .overlay {
                if let drag = app.matrixDrag {
                    MatrixDropOverlay(drag: drag)
                        .tint(accent)
                } else if let task = app.matrixTask {
                    MatrixPlacementOverlay(task: task)
                        .tint(accent)
                }
            }
            .animation(.snappy(duration: 0.2), value: app.matrixDrag == nil)
            .animation(.snappy(duration: 0.2), value: app.matrixTask == nil)
    }
}

/// Picks the page for the current sidebar selection.
struct DetailRouter: View {
    let selection: SidebarItem?
    let dayStart: Date

    var body: some View {
        switch selection {
        case .today, .none:
            TodayView(dayStart: dayStart)
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

/// Bridges UIKit-only entry points (Home Screen quick actions) into SwiftUI.
enum QuickActions {
    nonisolated(unsafe) static var pendingQuickEntry = false
}
