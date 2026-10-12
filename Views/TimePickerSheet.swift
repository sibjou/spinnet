import SwiftUI

struct TimePickerSheet: View {
    let title: String
    @Binding var time: Date
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}
