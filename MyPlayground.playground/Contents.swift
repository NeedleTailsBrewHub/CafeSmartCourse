import Foundation


// Structs - Value Types
struct PersonStruct {
    
    let id = UUID()
    let name: String
    var age: Int
    
    mutating func updateAge(_ newAge: Int) {
        age = newAge
    }
    
}

// Classes - Reference Types
class PersonClass {
    
    let id = UUID()
    let name: String
    var age: Int
    
    init(name: String, age: Int) {
        self.name = name
        self.age = age
    }
    
    
    func updateAge(_ newAge: Int) {
        age = newAge
    }
}

typealias Model = PersonClass

// Needs to be sendable // Final class means can't be changed // We are handling concurrency ourselves
@MainActor
final class PersonManager {
    var model: Model // not protecting with a lock
    let cache: PersonCache
    
    
    init(model: Model) {
        self.model = model
        self.cache = PersonCache(model: model)
    }
    
    func updateAge(_ newAge: Int) {
        model.updateAge(newAge)
    }
    
    func copyAge(from other: Model) {
        model.age = other.age
    }
    
    func replaceModel(_ newModel: Model) {
        model = newModel
    }
    
    //TODO: Synchonization between Structs
    
    
}

@MainActor
class PersonCache {
    var model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    func updateAge(_ newAge: Int) {
        model.updateAge(newAge)
    }
    
    func copyAge(from other: Model) {
        model.age = other.age
    }
    
    func replaceModel(_ newModel: Model) {
        model = newModel
    }
    
    //TODO: Synchonization between Structs
    
}


let initialModel = Model(name: "Alice", age: 22)
let incomingModel = Model(name: "Bob", age: 33)

let manager = PersonManager(model: initialModel)




print("START")
print("modelManager", manager.model.age)
print("CacheLayer", manager.cache.model.age)

print("Cache Update")
manager.updateAge(25)
manager.cache.updateAge(25)
print("modelManager", manager.model.age)
print("CacheLayer", manager.cache.model.age)

// Actors - Reference Types

nonisolated(unsafe) var inMutation = false

//func createRaceCondition() async {
//    
//    let manager = PersonManager(model: .init(name: "Alice Racer", age: 22))
//    
//    print("Start Race")
//    
//    await withTaskGroup(of: Void.self) { group in
//        
//        let numberOfTasks = 500
//        
//        
//        func mutateProperties(_ label: String, work: @escaping () -> Void) {
//            
//            for item in 0..<numberOfTasks { //not including 500, 0 to 499
//                
//                //Check if we are mutating a property
//                if inMutation {
//                    print("Data race detected")
//                }
//                inMutation = true
//                work()
//                
//                inMutation = false // This needs to happen before the next iteration so we do not have a data race
//            }
//            
//        }
//        
//        
//        //Will create our data race
//        group.addTask {
//            // Update Age
//            mutateProperties("Update age") {
//                manager.updateAge(Int.random(in: 0..<1000))
//            }
//        }
//        
//        //Cache Update
//        group.addTask {
//            //Update Age
//            mutateProperties("Update Cache age") {
//                manager.cache.updateAge(Int.random(in: 0..<1000))
//            }
//        }
//        
//        print("Finished data race check")
//        
//    }
//}
//
//Task {
//    await createRaceCondition()
//}

//We need to mutate on the Main Actor

var inMutationOnMainActor = false
var raceCount = 0


@MainActor
func withMainActorCheck(label: String, _ body: () -> Void) {
    if inMutationOnMainActor {
        raceCount += 1
        print("Data race detected on Main Actor \(raceCount)")
    }
    inMutationOnMainActor = true
    body()
    inMutationOnMainActor = false
}

func mainActorMutateWithOutRaceCondition() async {
    
    let manager = await PersonManager(model: .init(name: "Alice Racer", age: 22))
    
    print("Data race check")
    
    await MainActor.run {
        print("Model age", manager.model.age)
        print("Cache age", manager.cache.model.age)
    }
    
    
    await withTaskGroup(of: Void.self) { group in
        
        let numberOfIterations = 100
        
        group.addTask {
            for i in 0..<numberOfIterations {
                await MainActor.run {
                    withMainActorCheck(label: "Update age") {
                        manager.updateAge(Int.random(in: 0..<1000))
                    }
                }
            }
        }
        
        group.addTask {
            for i in 0..<numberOfIterations {
                await MainActor.run {
                    withMainActorCheck(label: "Update Cache age") {
                        manager.cache.updateAge(Int.random(in: 0..<1000))
                    }
                }
            }
        }
        
        print("Ended race check")
        await MainActor.run {
            print("Model age", manager.model.age)
            print("Cache age", manager.cache.model.age)
            print("Race count: \(raceCount)")
        }
    }
}

Task {
    await mainActorMutateWithOutRaceCondition()
}
