# Garden tracker plan

Goal: build a small tracker that answers two questions: what did I plant, and when should I check it again.

## first version

+ Add beds and containers
+ Record seed variety and planted date
* Weekly photo
- Reminder based on estimated germination time

## data model

```swift
struct Planting {
    let variety: String
    let plantedAt: Date
    var notes: [String]
}
```

Do not turn this into a social network. no profiles, likes or public garden pages. Export to plain JSON would be useful because the data shouldnt be trapped.

Open question: weather integration sounds helpful but is it worth needing location permission?
