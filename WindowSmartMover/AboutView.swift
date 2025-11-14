//
//  AboutView.swift
//  WindowSmartMover
//
//  Created by Masahito Zembutsu on 2025/10/18.
//

import SwiftUI

struct AboutView: View {
    // Info.plistから情報を取得
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private var currentDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: Date())
    }
    
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WindowSmartMover"
    }
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // アイコン
            Image(systemName: "rectangle.2.swap")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 30)
            
            // アプリ名
            Text(appName)
                .font(.title)
                .fontWeight(.bold)
            
            // バージョン情報
            VStack(spacing: 8) {
                HStack {
                    Text("バージョン:")
                        .foregroundColor(.secondary)
                    Text(appVersion)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("ビルド:")
                        .foregroundColor(.secondary)
                    Text(buildNumber)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("ビルド時刻:")
                        .foregroundColor(.secondary)
                    Text(currentDateTime)
                        .fontWeight(.semibold)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // 著作権情報
            VStack(spacing: 4) {
                Text("© 2025 @zembutsu (Masahito Zembutsu)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("マルチディスプレイ環境でウィンドウを簡単に移動")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // 閉じるボタン
            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.bottom)
        }
        .frame(width: 350, height: 420)
    }
}
