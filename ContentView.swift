                // Transfer Button
                Button(action: { startTransfer() }) {
                    HStack {
                        if isTransferring {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Transferring...")
                                .font(.headline)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Start Transfer")
                                .font(.headline)
                        }
                    }
                }
                .buttonStyle(.automatic)
                .disabled(isTransferring)
                .padding(.horizontal, 20)
                .padding(.vertical, 10) 