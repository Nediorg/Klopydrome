import SwiftUI

extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        )
    }
}

extension Binding where Value == Bool? {
    var orFalse: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue ?? false },
            set: { wrappedValue = $0 }
        )
    }

    var orTrue: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue ?? true },
            set: { wrappedValue = $0 }
        )
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
