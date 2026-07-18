//
//  MemberClaim.swift
//  splitr
//
//  Created by Muhammad Husni Romdhoni on 17/07/26.
//

import SwiftUI
import UIKit

struct MenuItemModel: Identifiable {
    let id = UUID()
    let name: String
    let qty: Int
    var price: Int
    var isChecked: Bool = false
}

struct BillModel: Identifiable {
    let id = UUID()
    let merchantName: String
    var items: [MenuItemModel]
    var tax: Int
    var service: Int
    var discount: Int
    var isExpanded: Bool = true
}

extension BillModel {
    var subtotal: Int {
        let itemsTotal = items.reduce(0) { $0 + ($1.price * $1.qty) }
        return itemsTotal + tax + service - discount
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct DashedDivider: View {
    var color: Color = Color.gray.opacity(0.4)
    var dash: [CGFloat] = [6, 4] // Angka pertama panjang line, angka kedua jarak antar line
    
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: dash))
            .foregroundColor(color)
            .frame(height: 1)
    }
}

struct CheckboxButton: View {
    @Binding var isChecked: Bool
    
    var body: some View {
        Button(action: { isChecked.toggle() }) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isChecked ?
                    AnyShapeStyle(
                        LinearGradient(
                            colors: [Color("Blue1"), Color("Blue2")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    ) :
                    AnyShapeStyle(Color(.systemGray5))
                )
                .frame(width: 24, height: 24)
                .overlay {
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

//MARK: view pas expanded
struct MenuItemRow: View {
    @Binding var item: MenuItemModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            //item + check
            HStack {
                Text(item.name)
                    .font(.subheadline)
//                    .fontWeight(.semibold)
                Spacer()
                CheckboxButton(isChecked: $item.isChecked)
            }
            
            //qty + price
            HStack {
                Text("x\(item.qty)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(item.price.formattedWithSeparator)")
                    .font(.subheadline)
//                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 22)
    }
}

//MARK: view utama (dinamis)
struct MemberClaim: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bills: [BillModel] = [
        BillModel(
            merchantName: "Alfamart Bill",
            items: [
                MenuItemModel(name: "Cimory hazelnut", qty: 1, price: 9_000),
                MenuItemModel(name: "Cimory hazelnut", qty: 1, price: 9_500, isChecked: true),
                MenuItemModel(name: "Cimory hazelnut", qty: 1, price: 9_000)
            ],
            tax: 8_000,
            service: 0,
            discount: 0,
            isExpanded: true
        ),
        BillModel(
            merchantName: "2nd Bills",
            items: [
                MenuItemModel(name: "Chitato", qty: 1, price: 11_500),
                MenuItemModel(name: "Coca Cola", qty: 1, price: 6_000)
            ],
            tax: 1_750,
            service: 0,
            discount: 0,
            isExpanded: false
        ),
        BillModel(
            merchantName: "3rd Bills",
            items: [
                MenuItemModel(name: "Ayam Goreng", qty: 1, price: 22_000),
                MenuItemModel(name: "Nasi Uduk", qty: 1, price: 7_000)
            ],
            tax: 2_900,
            service: 0,
            discount: 0,
            isExpanded: false
        )
    ]
    
    // Hitung total harga item yang di-ceklis
    private var totalCheckedPrice: Int {
        bills.flatMap { $0.items }
            .filter { $0.isChecked }
            .reduce(0) { $0 + ($1.price * $1.qty) }
    }
    
    // Hitung total jumlah qty item yang di-ceklis
    private var totalCheckedCount: Int {
        bills.flatMap { $0.items }
            .filter { $0.isChecked }
            .reduce(0) { $0 + $1.qty }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach($bills) { $bill in
                        VStack(spacing: 0) {
                            // MARK: header disclosure
                            Button(action: { bill.isExpanded.toggle() }) {
                                HStack {
                                    Text(bill.merchantName)
                                        .font(.title3)
                                        .bold(true)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .rotationEffect(.degrees(bill.isExpanded ? 180 : 0))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top)
                            .padding(.bottom, bill.isExpanded ? 8 : 20)
                            
                            if bill.isExpanded {
                                // list item + dashed divider
                                ForEach($bill.items) { $item in
                                    MenuItemRow(item: $item)
                                        .padding(.horizontal)
                                    DashedDivider()
                                        .padding(.horizontal)
                                }
                                
                                // MARK: summary rows
                                VStack(spacing: 12) {
                                    summaryRow(label: "Pajak", value: bill.tax)
                                    summaryRow(label: "Servis", value: bill.service)
                                    summaryRow(label: "Diskon", value: bill.discount)
                                    summaryRow(label: "Subtotal", value: bill.subtotal, weight: .semibold)
                                }
                                .padding()
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    }
                }
                .padding()
            }
            
            // MARK: Bottom Sticky Confirmation Footer
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your \(totalCheckedCount) item total")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(totalCheckedPrice.formattedWithSeparator)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                
                Button(action: {
                    // Konfirmasi action
                }) {
                    Text("Confirmation")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color("Blue1"), Color("Blue2")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12) // Penyeimbang padding agar menyatu dengan safe area bottom
            .background(
                Color.white
                    .clipShape(RoundedCorner(radius: 32, corners: [.topLeft, .topRight]))
                    .ignoresSafeArea(edges: .bottom)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: -5)
        }
        .background(Color(red: 0.90, green: 0.92, blue: 0.99).ignoresSafeArea())
        .navigationTitle("Split bill")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.black)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // helper buat baris Pajak/Servis/Diskon/Subtotal
    @ViewBuilder
    private func summaryRow(label: String, value: Int, weight: Font.Weight = .regular) -> some View {
        HStack {
            Text(label)
                .foregroundColor(weight != .regular ? .primary : .secondary)
            Spacer()
            Text("\(value.formattedWithSeparator)")
        }
        .font(weight != .regular ? .headline : .subheadline)
        .fontWeight(weight)
    }
}

// Shape kustom untuk membulatkan sudut tertentu (hanya atas kiri & atas kanan)
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// Extension Int untuk format ribuan dengan pemisah koma
extension Int {
    var formattedWithSeparator: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

#Preview {
    MemberClaim()
}
