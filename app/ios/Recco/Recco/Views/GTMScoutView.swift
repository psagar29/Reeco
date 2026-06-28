import SwiftUI

/// Identifiable wrapper so a prospect id can drive `.sheet(item:)`.
struct GTMProspectRef: Identifiable { let id: String }

/// Scout results: a graph of AI-found prospects around the run hub, plus a
/// swipeable card rail for quick browsing. Tapping a node or card opens detail.
/// Conceptually separate from the Brain (real people met).
struct GTMScoutView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isPresented: Bool

    @State private var selectedId: String?
    @State private var openProspect: GTMProspectRef?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 12) {
                header
                queryPill
                GTMScoutGraphView(
                    prospects: appModel.gtmProspects,
                    selectedId: $selectedId,
                    onOpen: { openProspect = GTMProspectRef(id: $0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                cardRail
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
        .sheet(item: $openProspect) { ref in
            GTMProspectDetailView(prospectId: ref.id)
                .environment(appModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scout").font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("AI-found prospects").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("\(appModel.gtmProspects.count)")
                .font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            Button { isPresented = false } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32).background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .accessibilityLabel("Close Scout")
        }
    }

    @ViewBuilder private var queryPill: some View {
        if let run = appModel.activeGtmRun {
            HStack(spacing: 6) {
                Image(systemName: "binoculars.fill").font(.caption2.weight(.bold))
                Text(run.label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Theme.accentSoft, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appModel.gtmProspects) { p in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedId = p.id }
                        openProspect = GTMProspectRef(id: p.id)
                    } label: {
                        prospectCard(p)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
            .padding(.bottom, 2)
        }
    }

    private func prospectCard(_ p: GTMProspectDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.surfaceStrong).frame(width: 30, height: 30)
                    Circle().strokeBorder(p.priority.color.opacity(0.9), lineWidth: 1.5).frame(width: 30, height: 30)
                    Text(p.initials).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.displayName).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if let line = p.roleCompanyLine {
                        Text(line).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 6) {
                PriorityPill(priority: p.priority, sent: p.isSent)
                if p.hasLinkedIn {
                    Image(systemName: "link").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(11)
        .frame(width: 190, alignment: .leading)
        .glassCard(corner: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selectedId == p.id ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
        )
    }
}
