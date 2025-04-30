//
//  PreferencesView.swift
//  Xenon-Transfer v2
//
//  Created by Myles Conti on 29/3/2025.
//
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: Settings
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.windowBackgroundColor))

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Project Details Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Project Details")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Project Name")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.projectName)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Date")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.date)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Crew Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Crew")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Director")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.director)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Director of Photography")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.dop)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Sound Recordist")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.soundRecordist)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("DIT")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.dit)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Technical Settings Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Technical Settings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Camera")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", text: $settings.camera)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Checksum Type")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            Picker("", selection: $settings.selectedChecksumType) {
                                ForEach(ChecksumType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            Text("Matrix Overlay")
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            
                            Toggle("", isOn: $settings.showMatrixOverlay)
                                .toggleStyle(SwitchToggleStyle())
                                .labelsHidden()
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 400, height: 500)
    }
}

