//
//  ContentView.swift
//  NotiflyIOSSample
//
//  Created by Minkyu Cho on 4/19/25.
//

import notifly_sdk
import SwiftUI

struct ContentView: View {
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Welcome to Notifly!")

                Button(action: {
                    Notifly.trackEvent(eventName: "sample_push_event")
                }) {
                    Text("Trigger Push Event")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: {
                    Notifly.trackEvent(eventName: "sample_popup_event")
                }) {
                    Text("Trigger Popup Event")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
            .onOpenURL { url in
                deepLinkManager.handleDeepLink(url)
            }
            .background(
                NavigationLink(
                    destination: deepLinkManager.deepLinkParameters.map { DeepLinkView(parameters: $0) },
                    isActive: Binding(
                        get: { deepLinkManager.deepLinkParameters != nil },
                        set: { if !$0 { deepLinkManager.deepLinkParameters = nil } }
                    ),
                    label: { EmptyView() }
                )
            )
        }
    }
}

#Preview {
    ContentView()
}
