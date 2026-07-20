//
//  PeopleListSheet.swift
//  splitr
//

import SwiftUI

struct PeopleListSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @Binding var people: [Person]
    @State private var showingAddAlert = false
    @State private var newName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Header
            ZStack {
                Text("List people")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                
                HStack {
                    // Close Button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.gray)
                            .frame(width: 56, height: 56)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Add New Button
                    Button {
                        addNewPerson()
                    } label: {
                        Text("Add new")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.black.opacity(0.7))
                            .padding(.horizontal, 20)
                            .frame(height: 56)
                            .background(.white)
                            .clipShape(Capsule())
                            .shadow(
                                color: .black.opacity(0.08),
                                radius: 20,
                                x: 0,
                                y: 8
                            )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // MARK: - People List
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(people) { person in
                        PersonRow(person: person)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
        }
        .background(
            Color(
                red: 0.98,
                green: 0.98,
                blue: 0.98
            )
        )
        .alert("Add New Person", isPresented: $showingAddAlert) {
            TextField("Name", text: $newName)
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let avatar = "avatar\(Int.random(in: 1...4))"
                    let newPerson = Person(name: name, avatar: avatar)
                    people.append(newPerson)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the name of the new person.")
        }
    }
    
    // MARK: - Add New Person
    private func addNewPerson() {
        newName = ""
        showingAddAlert = true
    }
}


// MARK: - Person Row

struct PersonRow: View {
    
    let person: Person
    
    var body: some View {
        HStack(spacing: 16) {
            
            Image(person.avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.15),
                            lineWidth: 1
                        )
                }
            
            Text(person.name)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.black)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 80)
        .background(.white)
        .clipShape(
            RoundedRectangle(cornerRadius: 24)
        )
    }
}


// MARK: - Person Model

struct Person: Identifiable {
    let id = UUID()
    let name: String
    let avatar: String
}


// MARK: - Preview

#Preview {
    PeopleListSheet(people: .constant([
        Person(name: "Hano Ngoding", avatar: "avatar1"),
        Person(name: "Noorfi Github", avatar: "avatar2"),
        Person(name: "Husni Ilustrator", avatar: "avatar3"),
        Person(name: "Bray Layout", avatar: "avatar4")
    ]))
}
