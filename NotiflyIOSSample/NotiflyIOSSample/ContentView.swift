//
//  ContentView.swift
//  NotiflyIOSSample
//
//  Created by Minkyu Cho on 4/19/25.
//

import notifly_sdk
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Button(action: {
                Notifly.setUserId(userId: "sample")
                Notifly.trackEvent(eventName: "sample_event")
            }) {
                Text("Trigger Event")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
