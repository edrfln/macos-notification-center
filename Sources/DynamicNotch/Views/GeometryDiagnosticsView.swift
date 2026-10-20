import SwiftUI

/// Diagnostics HUD displayed in the expanded tray to verify screen geometry,
/// hardware notch detection, and live mouse tracking state.
public struct GeometryDiagnosticsView: View {
    let geometry: ScreenGeometry
    @Bindable var viewModel: NotchViewModel
    let controller: NotchWindowController
    
    public init(geometry: ScreenGeometry, viewModel: NotchViewModel, controller: NotchWindowController) {
        self.geometry = geometry
        self.viewModel = viewModel
        self.controller = controller
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("PHASE 1 & 2 GEOMETRY DIAGNOSTICS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.9))
                Spacer()
                Text(geometry.hasHardwareNotch ? "HARDWARE NOTCH" : "EXTERNAL DISPLAY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(geometry.hasHardwareNotch ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
            
            // Metrics grid
            VStack(alignment: .leading, spacing: 3) {
                metricRow(label: "Screen Frame", value: "\(Int(geometry.screenFrame.width)) × \(Int(geometry.screenFrame.height)) pt (Origin: \(Int(geometry.screenFrame.origin.x)), \(Int(geometry.screenFrame.origin.y)))")
                metricRow(label: "Notch Cutout", value: "\(String(format: "%.1f", geometry.notchWidth)) × \(String(format: "%.1f", geometry.notchHeight)) pt")
                metricRow(label: "Safe Area Top", value: "\(String(format: "%.1f", geometry.safeAreaInsetsTop)) pt")
                metricRow(label: "Notch Center X", value: "\(String(format: "%.1f", geometry.notchCenterX)) pt")
                metricRow(label: "Current State", value: viewModel.state.displayName)
                metricRow(label: "Mouse In Window", value: viewModel.isMouseInside ? "YES (Tracking Active)" : "NO")
            }
            .padding(6)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
            
            // Manual State & Simulation Controls
            HStack(spacing: 5) {
                Button("Idle") {
                    controller.transition(to: .idle)
                }
                .buttonStyle(NotchActionButtonStyle(color: .gray))
                
                Button("♪ Media") {
                    viewModel.mediaManager.startSimulatedPlayback()
                    if let media = viewModel.mediaManager.currentMedia {
                        controller.transition(to: .mediaExpanded(media))
                    }
                }
                .buttonStyle(NotchActionButtonStyle(color: .pink))
                
                Spacer()
                
                Button("+ Slack") {
                    MockNotificationEmitter.emitSlack(to: viewModel.notificationManager)
                }
                .buttonStyle(NotchActionButtonStyle(color: .blue))
                
                Button("+ GitHub") {
                    MockNotificationEmitter.emitGitHub(to: viewModel.notificationManager)
                }
                .buttonStyle(NotchActionButtonStyle(color: .purple))
                
                Button("+ Burst (3)") {
                    MockNotificationEmitter.emitBurst(count: 3, to: viewModel.notificationManager)
                }
                .buttonStyle(NotchActionButtonStyle(color: .orange))
            }
            .padding(.top, 2)
        }
    }
    
    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 95, alignment: .leading)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}
