
//
//  SplitBillNameCard.swift
//  splitr
//

import SwiftUI

struct SplitBillNameCard: View {

    @Binding var billName: String
    /// When false the field is read-only (e.g. a closed room).
    var isEditable: Bool = true
    /// Fired when the host finishes editing (return key / focus loss) so the
    /// caller can persist — we don't write the store on every keystroke.
    var onCommit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Bills name")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("Enter bill name", text: $billName)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .disabled(!isEditable)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { onCommit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { onCommit() }
                }

            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(height: 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {

    @Previewable @State var billName = "Mie Gacoan Jogja"

    ZStack {
        Color("PrimaryBackground")
            .ignoresSafeArea()

        SplitBillNameCard(billName: $billName)
            .padding(24)
    }
}
