import SwiftUI

/// Today is the first screen; every other page is one tap away under the Lists button.
struct WatchRootView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: pathBinding) {
            WatchTodayView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            model.show(.lists)
                        } label: {
                            // The toolbar fills this button with the tint; keep the glyph readable on it.
                            Image(systemName: "list.bullet")
                                .fontWeight(.semibold)
                                .foregroundStyle(.black)
                        }
                        .accessibilityLabel("Lists")
                    }
                }
                .navigationDestination(for: WatchRoute.self) { route in
                    destination(for: route)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshDay() }
        }
    }

    private var pathBinding: Binding<[WatchRoute]> {
        Binding(get: { model.path }, set: { model.path = $0 })
    }

    @ViewBuilder
    private func destination(for route: WatchRoute) -> some View {
        switch route {
        case .lists: WatchListsView()
        case .upcoming: WatchUpcomingView()
        case .priority: WatchPriorityView()
        case .group(let id): WatchGroupView(groupID: id)
        case .task(let task): WatchTaskDetailView(task: task)
        }
    }
}
