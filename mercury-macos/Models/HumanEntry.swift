import Foundation

/* Similar to a Typescript interface, this struct defines the shape/structure of a journal entry object.
Key differences from Typescript:
- Structs can include implementations (like createNew())
- Structure create value types
- Identifiable protocol is used to identify entries
*/
struct HumanEntry: Identifiable {
    // Unique identifier for each entry, used to distinguish between entries
    let id: UUID
    // Display date of the entry (e.g. "Apr 15")
    let date: String
    // Name of the markdown file where this entry is stored
    // I changed filename to var because I want to make it editable
    var filename: String
    // Preview text that can be modified, shows a snippet of the entry's content
    // var means it can change after creation, while let properties are immutable
    var previewText: String
    
    static func createNew() -> HumanEntry {
        let id = UUID()
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let dateString = dateFormatter.string(from: now)
        
        // For display
        dateFormatter.dateFormat = "MMM d"
        let displayDate = dateFormatter.string(from: now)
        
        return HumanEntry(
            id: id,
            date: displayDate,
            filename: "[\(id)]-[\(dateString)].md",
            // previewText starts empty but gets populated later in mercuryApp.swift when entries are loaded or saved. 
            // It's used to show truncated previews (first 30 characters) of each entry in the sidebar history list, helping users identify their past entries.
            previewText: ""
        )
    }
}