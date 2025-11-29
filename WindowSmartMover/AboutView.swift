//
//  AboutView.swift
//  WindowSmartMover
//
//  Created by Masahito Zembutsu on 2025/10/18.
//

import SwiftUI

struct AboutView: View {
    // Get info from Info.plist
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WindowSmartMover"
    }
    
    private let githubURL = "https://github.com/zembutsu/WindowSmartMover"
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "rectangle.2.swap")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .padding(.top, 20)
            
            // App name
            VStack(spacing: 4) {
                Text("Tsubame")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Window Smart Mover")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Version info
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Version")
                        .foregroundColor(.secondary)
                    Text(appVersion)
                        .fontWeight(.semibold)
                }
                
                HStack(spacing: 4) {
                    Text("Build")
                        .foregroundColor(.secondary)
                    Text(buildNumber)
                        .fontWeight(.semibold)
                }
            }
            .font(.subheadline)
            
            Divider()
            
            // Shortcuts
            GroupBox(label: Text(NSLocalizedString("Shortcuts", comment: "")).font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    let mod = HotKeySettings.shared.getModifierString()
                    
                    HStack {
                        Text(NSLocalizedString("Move between screens", comment: ""))
                            .frame(width: 130, alignment: .leading)
                            .font(.subheadline)
                        Text("\(mod)→ / \(mod)←")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("Snapshot", comment: ""))
                            .frame(width: 130, alignment: .leading)
                            .font(.subheadline)
                        Text("\(mod)↑ / \(mod)↓")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("Position adjustment", comment: ""))
                            .frame(width: 130, alignment: .leading)
                            .font(.subheadline)
                        Text("\(mod)W/A/S/D")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Information
            GroupBox(label: Text(NSLocalizedString("Information", comment: "")).font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(NSLocalizedString("Developer", comment: ""))
                            .frame(width: 70, alignment: .leading)
                            .font(.subheadline)
                        Text("Masahito Zembutsu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("License", comment: ""))
                            .frame(width: 70, alignment: .leading)
                            .font(.subheadline)
                        Text("MIT License")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("GitHub")
                            .frame(width: 70, alignment: .leading)
                            .font(.subheadline)
                        Link("zembutsu/WindowSmartMover", destination: URL(string: githubURL)!)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Copyright
            Text("© 2025 @zembutsu")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Close button
            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.bottom)
        }
        .padding(.horizontal)
        .frame(width: 360, height: 520)
    }
}
