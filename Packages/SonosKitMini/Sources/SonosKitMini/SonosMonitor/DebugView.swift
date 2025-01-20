//
//  ContentView.swift
//  Listener
//
//  Created by Nick Hayward on 1/3/25.
//

import SwiftUI

struct DebugView: View {
    @StateObject private var viewModel = SonosMonitor()
    
    var body: some View {
        ScrollView {
            Text(viewModel.isConnectedToWiFi ? "Wifi" : "No Wifi")
//            Button {
//                viewModel.sendSubscribe()
//            } label: {
//                Text("Subsribe")
//            }
//            
            LazyVStack(spacing: 16) {
                ForEach(viewModel.devices.filter({ !$0.isHidden }).sorted(by: { $0.name < $1.name })) { device in
                    DeviceCard(device: device)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical)
//            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.devices)
        }
        .task {
            await viewModel.startListening()
        }
    }
}

struct DeviceHeader: View {
    let device: SonosDevice
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.name)
                Text(device.id)
                    .font(.headline)
                Text(device.ip)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Rooms: ")
                    Text(device.rooms.map { $0.name }.joined(separator: ", "))
                }
                
                Text(device.trackID ?? "")
                Text(device.musicServiceType.title)
            }
            Spacer()
            
            // Volume Controls
            HStack(spacing: 8) {
                Image(systemName: device.groupIsMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundColor(device.groupIsMuted == true ? .red : .blue)
                  
                Text("\(device.groupVolume)%")
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .animation(.spring.speed(2), value: device.groupVolume)
                    .frame(width: 38, alignment: .trailing)
                    .fontDesign(.rounded)
                    .bold()
            }
            if device.isTVMode {
                Image(systemName: "tv")
            }
            // Playback state indicator
            if !device.transportState.isEmpty {
                Image(systemName: device.transportState.lowercased() == "playing" ? "play.circle.fill" : "pause.circle.fill")
                    .foregroundColor(device.transportState.lowercased() == "playing" ? .green : .orange)
                    .font(.title)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct NowPlayingView: View {
    let metadata: SonosTrackMetadata
    let streamInfo: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Now Playing")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(metadata.title.unescaped)
                .font(.title2)
                .bold()
                .lineLimit(2)
            Text(metadata.album)
            Text(metadata.albumArtURI ?? "No Album URL")
            Text(metadata.creator)
                .font(.body)
                .foregroundColor(.secondary)
            
            if let streamInfo = streamInfo {
                Text(streamInfo)
                    .font(.caption)
                    .padding(4)
                    .background(.thinMaterial)
                    .cornerRadius(4)
            }
            
            Text(metadata.streamInfo?.info?.description ?? "Unknown")
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct NextView: View {
    let device: SonosDevice
    let metadata: SonosTrackMetadata
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(metadata.title.unescaped)
                .font(.title2)
                .bold()
                .lineLimit(2)
            Text(metadata.album)
            Text(metadata.albumArtURI ?? "No Album URL")
            Text(metadata.creator)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}

struct ProgressBarView: View {
    let device: SonosDevice
    
    var body: some View {
        let isPlaying = device.transportState.lowercased() == "playing" && formatTimeString(device.currentTrackDuration) != "0:00"
        TimelineView(.animation(minimumInterval: 0.01, paused: !isPlaying)) { context in
            let elapsedTime = isPlaying ? Int(context.date.timeIntervalSince(device.lastUpdate)) : 0
            let progress = device.currentTime.toDuration() + .seconds(elapsedTime)
            let totalDuration = device.currentTrackDuration.toDuration()
            
            VStack(spacing: 4) {
                HStack {
                    Text(progress, format: .time(pattern: .minuteSecond))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    Spacer()
                    Text(formatTimeString(device.currentTrackDuration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            
                let progress = totalDuration.components.seconds > 0
                ? min(max(Double(progress.components.seconds) / Double(totalDuration.components.seconds), 0), 1)
                : 0

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(height: 4)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
        }
    }
    
    func formatTimeString(_ timeString: String) -> String {
        return timeString.isEmpty ? "0:00" : timeString
    }
}

struct DeviceCard: View {
    let device: SonosDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceHeader(device: device)
            
//            if let dialogLevel = device.dialogLevel {
//                Text(dialogLevel, format: .number)
//            }
//            
//            if let nightMode = device.nightMode {
//                Text(nightMode ? "NightMode" : "Nightmode off")
//            }
//            
            if let crossfadeEnabled = device.isCrossfaded {
                Text(crossfadeEnabled ? "Crossfade On" : "Crossfade Off")
            }
            
            AsyncImage(url: device.sonosAlbumARTURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .cornerRadius(8)
            } placeholder: {
                Rectangle()
                    .foregroundStyle(.thinMaterial)
                    .frame(width: 200, height: 200)
                    .cornerRadius(8)
            }
            .frame(width: 200, height: 200)
            Text(device.currentTrackURI)
            if let currentMetadata = device.currentTrackMetadata {
                VStack(alignment: .leading, spacing: 4) {
                    NowPlayingView(metadata: currentMetadata, streamInfo: currentMetadata.streamInfo?.description)
                    ProgressBarView(device: device)
                }
                
                if let nextTrackMetadata = device.nextTrackMetadata {
                    VStack(alignment: .leading, spacing: 4) {
                        NextView(device: device, metadata: nextTrackMetadata)
                    }
                }
            } else {
                Text("Waiting for updates...")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(16)
        .shadow(radius: 2)
        .padding(.horizontal)
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    DebugView()
}
