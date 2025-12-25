import Foundation
import SpriteKit

// MARK: - Base Player Building
class PlayerBuilding {
    let type: PlayerBuildingType
    var gridPosition: GridPosition = GridPosition(x: 0, y: 0)
    weak var node: SKNode?
    weak var sourceDepot: Depot?
    weak var primaryServicer: Depot?

    // Quota system (what's assigned/requested)
    var survivorQuota: Int = 0
    var woodQuota: Int = 0
    var bulletQuota: Int = 0
    
    // Actual present resources
    var presentSurvivors: Int = 0
    var presentWood: Int = 0
    var presentBullets: Int = 0
    
    // Status indicators
    var indicatorNode: SKNode?
    
    init(type: PlayerBuildingType) {
        self.type = type
    }
    
    var blocksMovement: Bool {
        return type == .barricade
    }
    
    var isDestroyed: Bool { false }
    
    // Check if building needs resources
    var needsSurvivors: Bool { presentSurvivors < survivorQuota }
    var needsWood: Bool { presentWood < woodQuota }
    var needsBullets: Bool { presentBullets < bulletQuota }
    var needsAnyResource: Bool { needsSurvivors || needsWood || needsBullets }
    
    // Calculate deficit for prioritization
    var survivorDeficit: Int { max(0, survivorQuota - presentSurvivors) }
    var woodDeficit: Int { max(0, woodQuota - presentWood) }
    var bulletDeficit: Int { max(0, bulletQuota - presentBullets) }
    var totalDeficit: Int { survivorDeficit + woodDeficit + bulletDeficit }
    
    func createNode() -> SKNode {
        let node = SKShapeNode(rectOf: type.size)
        node.fillColor = type.color
        node.strokeColor = .white
        node.lineWidth = 1
        node.position = gridPosition.toScenePosition()
        node.zPosition = ZPosition.playerBuildings
        
        self.node = node
        return node
    }
    
    func update(deltaTime: TimeInterval, gameState: GameState) {
        // Check if servicer is missing or dead, find a new one
        if primaryServicer == nil || primaryServicer!.isDestroyed {
            assignPrimaryServicer(gameState: gameState)
        }
        updateIndicator()
    }
    
    func assignPrimaryServicer(gameState: GameState) {
        let functionalDepots = gameState.depots.filter { !$0.isDestroyed }
        guard !functionalDepots.isEmpty else { return }
        
        let sorted = functionalDepots.sorted { 
            self.gridPosition.distance(to: $0.gridPosition) < self.gridPosition.distance(to: $1.gridPosition) 
        }
        
        let shortestDist = self.gridPosition.distance(to: sorted[0].gridPosition)
        let candidates = sorted.filter { 
            self.gridPosition.distance(to: $0.gridPosition) == shortestDist 
        }
        
        self.primaryServicer = candidates.randomElement()
    }
    
    func updateIndicator() {
        indicatorNode?.removeFromParent()
        indicatorNode = nil
        
        guard needsAnyResource, let parentNode = node else { return }
        
        let indicator = SKLabelNode(fontNamed: "Apple Color Emoji")
        indicator.fontSize = 10
        
        var text = ""
        if needsSurvivors { text += "👩🏿" }
        if needsWood      { text += "🪵" }
        if needsBullets   { text += "🔫" }
        
        indicator.text = text
        indicator.position = CGPoint(x: 0, y: 8)
        indicator.zPosition = ZPosition.buildingIndicators
        parentNode.addChild(indicator)
        indicatorNode = indicator
    }
    
    func receiveSurvivor() {
        presentSurvivors += 1
        updateIndicator()
    }
    
    func receiveWood(_ amount: Int) {
        presentWood += amount
        updateIndicator()
    }
    
    func receiveBullets(_ amount: Int) {
        presentBullets += amount
        updateIndicator()
    }
    
    func retreat(gameState: GameState) {
        // Override in subclasses
    }
    
    func takeDamage(_ amount: Int) {
        // Override in subclasses - barricades take wood damage
        // Other buildings might have different damage handling
    }
}

// MARK: - Depot
class Depot: PlayerBuilding {
    var storedWood: Int = 0
    var storedBullets: Int = 0
    var heldSurvivors: Int = 0
    var wasAbandoned: Bool = false  // Only true when retreat button is used AND moved to new depot
    
    var prioritizations: [DepotPrioritization] = []
    var showDependencies: Bool = false
    var hasHeavyPour: Bool = false
    var connectionLines: [SKNode] = []
    
    // Track present vs expected survivors separately
    var presentSurvivorsCount: Int = 0
    
    override var isDestroyed: Bool { 
        // Depot is only destroyed if it has been completely emptied AND no survivors are returning to it
        // AND it wasn't just retreated from
        return wasAbandoned || (heldSurvivors <= 0 && storedWood <= 0 && storedBullets <= 0 && presentSurvivorsCount <= 0)
    }
    
    // Depot needs - based on stored resources vs quota
    override var needsSurvivors: Bool { heldSurvivors < survivorQuota }
    override var needsWood: Bool { storedWood < woodQuota }
    override var needsBullets: Bool { storedBullets < bulletQuota }
    
    override var survivorDeficit: Int { max(0, survivorQuota - heldSurvivors) }
    override var woodDeficit: Int { max(0, woodQuota - storedWood) }
    override var bulletDeficit: Int { max(0, bulletQuota - storedBullets) }
    
    init() {
        super.init(type: .depot)
    }
    
    override func createNode() -> SKNode {
        let node = super.createNode()
        
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.fontSize = 8
        label.fontColor = .white
        label.text = "👤\(heldSurvivors)"
        label.verticalAlignmentMode = .center
        label.name = "survivorLabel"
        node.addChild(label)
        
        return node
    }
    
    func updateLabel() {
        if let label = node?.childNode(withName: "survivorLabel") as? SKLabelNode {
            label.text = "👤\(heldSurvivors)"
        }
        
        // Heavy pour indicator
        if hasHeavyPour {
            if node?.childNode(withName: "heavyPourIndicator") == nil {
                let indicator = SKLabelNode(fontNamed: "Apple Color Emoji")
                indicator.text = "🌠"
                indicator.fontSize = 10
                indicator.position = CGPoint(x: 8, y: 8)
                indicator.name = "heavyPourIndicator"
                node?.addChild(indicator)
            }
        } else {
            node?.childNode(withName: "heavyPourIndicator")?.removeFromParent()
        }
    }
    
    func depositSurvivor() {
        heldSurvivors += 1
        presentSurvivors += 1
        presentSurvivorsCount = presentSurvivors
        updateLabel()
    }
    
    func withdrawSurvivor() -> Bool {
        if heldSurvivors > 0 {
            heldSurvivors -= 1
            presentSurvivors -= 1
            presentSurvivorsCount = max(0, presentSurvivors)
            updateLabel()
            return true
        }
        return false
    }
    
    func storeResources(wood: Int = 0, bullets: Int = 0) {
        storedWood += wood
        storedBullets += bullets
    }
    
    // Override receive methods to use stored resources
    override func receiveWood(_ amount: Int) {
        storedWood += amount
        updateLabel()
    }
    
    override func receiveBullets(_ amount: Int) {
        storedBullets += amount
        updateLabel()
    }
    
    func withdrawWood(_ amount: Int) -> Int {
        let actual = min(amount, storedWood)
        storedWood -= actual
        return actual
    }
    
    func withdrawBullets(_ amount: Int) -> Int {
        let actual = min(amount, storedBullets)
        storedBullets -= actual
        return actual
    }
    
    func getBuildingsInRange(gameState: GameState) -> [PlayerBuilding] {
        var buildings: [PlayerBuilding] = []
        for building in gameState.allPlayerBuildings {
            guard building !== self else { continue }
            if gridPosition.isWithinRadius(GameBalance.depotBuildRadius, of: building.gridPosition) {
                buildings.append(building)
            }
        }
        return buildings
    }
    
    func getBuildingWithHighestNeed(gameState: GameState) -> PlayerBuilding? {
        let inRange = getBuildingsInRange(gameState: gameState)
        return inRange.filter { $0.needsAnyResource }.max { $0.totalDeficit < $1.totalDeficit }
    }
    
    override func update(deltaTime: TimeInterval, gameState: GameState) {
        super.update(deltaTime: deltaTime, gameState: gameState)
        
        prioritizations = prioritizations.filter { p in
            if let time = p.timeRemaining {
                return time > 0
            }
            return true
        }
        
        for i in prioritizations.indices {
            if prioritizations[i].timeRemaining != nil {
                prioritizations[i].timeRemaining! -= deltaTime
            }
        }
        
        dispatchResources(gameState: gameState, deltaTime: deltaTime)
    }
    
    private var dispatchCooldown: TimeInterval = 0
    
    private func dispatchResources(gameState: GameState, deltaTime: TimeInterval) {
        dispatchCooldown -= deltaTime
        guard dispatchCooldown <= 0 else { return }
        dispatchCooldown = 0.5
        
        // First priority: Service buildings in range (can drain past quota)
        if let target = getBuildingWithHighestNeed(gameState: gameState) {
            if dispatchToBuilding(target, canDrainPastQuota: true, gameState: gameState) {
                return
            }
        }
        
        // Second priority: Service other depots that need resources (only from surplus)
        if let needyDepot = getDepotWithHighestNeed(gameState: gameState) {
            if dispatchToBuilding(needyDepot, canDrainPastQuota: false, gameState: gameState) {
                return
            }
        }
    }
    
    private func dispatchToBuilding(_ target: PlayerBuilding, canDrainPastQuota: Bool, gameState: GameState) -> Bool {
        // Calculate what we can send based on whether we can go past quota
        let availableSurvivors = canDrainPastQuota ? heldSurvivors : max(0, heldSurvivors - survivorQuota)
        let availableWood = canDrainPastQuota ? storedWood : max(0, storedWood - woodQuota)
        let availableBullets = canDrainPastQuota ? storedBullets : max(0, storedBullets - bulletQuota)
        
        // Need at least 1 survivor to dispatch anything (as driver or walker)
        guard heldSurvivors > 0 else { return false }
        
        // Dispatch survivors first (they walk, don't need a truck driver)
        if target.needsSurvivors && availableSurvivors > 0 {
            if withdrawSurvivor() {
                let survivor = FreeSurvivor(at: gridPosition)
                survivor.destinationBuilding = target
                _ = survivor.setDestination(target.gridPosition, map: gameState.map)
                gameState.addFreeSurvivor(survivor)
                return true
            }
        }
        
        // Dispatch wood truck
        if target.needsWood && availableWood >= GameBalance.truckCapacity && heldSurvivors > 0 {
            let amount = min(GameBalance.truckCapacity, target.woodDeficit, availableWood)
            let wasSurplus = heldSurvivors > survivorQuota
            let wood = withdrawWood(amount)
            if withdrawSurvivor() {
                let truck = Truck(at: gridPosition, sourceDepot: self)
                truck.carryingWood = wood
                truck.targetBuilding = target
                truck.wasSurplusSurvivor = wasSurplus
                _ = truck.setDestination(target.gridPosition, map: gameState.map)
                gameState.addTruck(truck)
                return true
            } else {
                storedWood += wood
            }
        }
        
        // Dispatch bullet truck
        if target.needsBullets && availableBullets >= GameBalance.truckCapacity && heldSurvivors > 0 {
            let amount = min(GameBalance.truckCapacity, target.bulletDeficit, availableBullets)
            let wasSurplus = heldSurvivors > survivorQuota
            let bullets = withdrawBullets(amount)
            if withdrawSurvivor() {
                let truck = Truck(at: gridPosition, sourceDepot: self)
                truck.carryingBullets = bullets
                truck.targetBuilding = target
                truck.wasSurplusSurvivor = wasSurplus
                _ = truck.setDestination(target.gridPosition, map: gameState.map)
                gameState.addTruck(truck)
                return true
            } else {
                storedBullets += bullets
            }
        }
        
        return false
    }
    
    func getDepotWithHighestNeed(gameState: GameState) -> Depot? {
        // Find depots in range that need resources
        // Only consider depots that this depot can reach (within 8 blocks)
        let depotsInRange = gameState.depots.filter { depot in
            depot !== self && 
            !depot.isDestroyed && 
            gridPosition.distance(to: depot.gridPosition) <= 8
        }
        
        // Filter to those that need resources AND we have surplus to give
        let needyDepots = depotsInRange.filter { depot in
            let depotNeedsSurvivors = depot.heldSurvivors < depot.survivorQuota
            let depotNeedsWood = depot.storedWood < depot.woodQuota
            let depotNeedsBullets = depot.storedBullets < depot.bulletQuota
            
            let weHaveSurplusSurvivors = heldSurvivors > survivorQuota
            let weHaveSurplusWood = storedWood > woodQuota
            let weHaveSurplusBullets = storedBullets > bulletQuota
            
            return (depotNeedsSurvivors && weHaveSurplusSurvivors) ||
                   (depotNeedsWood && weHaveSurplusWood) ||
                   (depotNeedsBullets && weHaveSurplusBullets)
        }
        
        // Return depot with highest deficit
        return needyDepots.max { d1, d2 in
            let deficit1 = (d1.survivorQuota - d1.heldSurvivors) + 
                          (d1.woodQuota - d1.storedWood) + 
                          (d1.bulletQuota - d1.storedBullets)
            let deficit2 = (d2.survivorQuota - d2.heldSurvivors) + 
                          (d2.woodQuota - d2.storedWood) + 
                          (d2.bulletQuota - d2.storedBullets)
            return deficit1 < deficit2
        }
    }
    
    func addPrioritization(_ prioritization: DepotPrioritization) {
        prioritizations.append(prioritization)
        if prioritization.mode == .heavyPour {
            hasHeavyPour = true
        }
        updateLabel()
    }
    
    func removeLastPrioritization() {
        if let last = prioritizations.popLast() {
            if last.mode == .heavyPour {
                hasHeavyPour = prioritizations.contains { $0.mode == .heavyPour }
            }
        }
        updateLabel()
    }
    
    func removeAllPrioritizations() {
        prioritizations.removeAll()
        hasHeavyPour = false
        updateLabel()
    }
    
    override func retreat(gameState: GameState) {
        // Check if there's another depot to retreat to
        let otherDepot = gameState.findNearestDepot(to: gridPosition, excluding: self)
        
        if storedWood > 0 || storedBullets > 0 {
            let dropped = gameState.map.dropResources(at: gridPosition, wood: storedWood, bullets: storedBullets)
            gameState.addDroppedResource(dropped)
        }
        
        for _ in 0..<heldSurvivors {
            let survivor = FreeSurvivor(at: gridPosition)
            if let nearestDepot = otherDepot {
                survivor.destinationDepot = nearestDepot
                _ = survivor.setDestination(nearestDepot.gridPosition, map: gameState.map)
            }
            gameState.addFreeSurvivor(survivor)
        }
        
        heldSurvivors = 0
        storedWood = 0
        storedBullets = 0
        
        // Only mark as abandoned if there was another depot to go to
        // Otherwise this depot is still "active" even if empty
        if otherDepot != nil {
            wasAbandoned = true
        }
    }
}

// MARK: - Workshop
class Workshop: PlayerBuilding {
    weak var targetBuilding: CityBuilding?
    var targetDebris: DebrisObject?
    var targetTileType: TileType?
    var targetTent: Tent?
    var collectedWood: Int = 0
    var collectedBullets: Int = 0
    var collectedSurvivors: Int = 0
    var dynamiteProgress: Int = 0
    var isFinished: Bool = false
    var isOnDynamite: Bool = false
    var linkedBridgeId: Int?
    var needsCloseResource: Bool = false
    
    private var collectionTimer: TimeInterval = 0
    private var noiseAccumulator: Int = 0
    private var truckSpawnAccumulator: TimeInterval = 0
    
    init() {
        super.init(type: .workshop)
        survivorQuota = 1
    }
    
    override func update(deltaTime: TimeInterval, gameState: GameState) {
        super.update(deltaTime: deltaTime, gameState: gameState)
        
        guard presentSurvivors > 0, !isFinished else { return }
        
        if needsCloseResource {
            collectionTimer += deltaTime
            if collectionTimer >= 1.0 {
                collectionTimer = 0
                finishWorkshop(gameState: gameState)
            }
            return
        }
        
        if isOnDynamite {
            updateDynamitePlacement(deltaTime: deltaTime, gameState: gameState)
            return
        }
        
        if targetTileType == .debris {
            updateDebrisClearing(deltaTime: deltaTime, gameState: gameState)
            return
        }
        
        if targetTileType == .tent {
            updateTentClearing(deltaTime: deltaTime, gameState: gameState)
            return
        }
        
        if let debris = targetDebris {
            updateDebrisObjectCollection(from: debris, deltaTime: deltaTime, gameState: gameState)
            updateTruckSpawning(deltaTime: deltaTime, gameState: gameState)
            return
        }
        
        if let target = targetBuilding {
            updateResourceCollection(from: target, deltaTime: deltaTime, gameState: gameState)
        }
        
        updateTruckSpawning(deltaTime: deltaTime, gameState: gameState)
    }
    
    private func updateDebrisObjectCollection(from debris: DebrisObject, deltaTime: TimeInterval, gameState: GameState) {
        guard debris.hasResources else {
            // Debris is empty - request close resource (this will clear both workshop and debris)
            requestCloseResource()
            return
        }
        
        let rate = calculateCollectionRate()
        collectionTimer += deltaTime * rate
        
        if collectionTimer >= 1.0 {
            collectionTimer -= 1.0
            
            if debris.resources.survivors > 0 {
                debris.resources.survivors -= 1
                collectedSurvivors += 1
            } else if debris.resources.wood > 0 {
                debris.resources.wood -= 1
                collectedWood += 1
            } else if debris.resources.bullets > 0 {
                debris.resources.bullets -= 1
                collectedBullets += 1
            }
            
            noiseAccumulator += 1
            debris.updateVisual()
            
            if noiseAccumulator >= GameBalance.workshopMediumNoiseThreshold {
                noiseAccumulator = 0
                gameState.createNoiseEvent(at: gridPosition, level: .medium)
            }
        }
    }
    
    private func updateTentClearing(deltaTime: TimeInterval, gameState: GameState) {
        guard let tent = targetTent else {
            requestCloseResource()
            return
        }
        
        let rate = calculateCollectionRate()
        collectionTimer += deltaTime * rate
        
        if collectionTimer >= 1.0 {
            collectionTimer -= 1.0
            
            if tent.survivors > 0 {
                tent.survivors -= 1
                collectedSurvivors += 1
            } else if tent.wood > 0 {
                tent.wood -= 1
                collectedWood += 1
            } else if tent.bullets > 0 {
                tent.bullets -= 1
                collectedBullets += 1
            }
            
            noiseAccumulator += 1
            
            if noiseAccumulator >= GameBalance.workshopMediumNoiseThreshold {
                noiseAccumulator = 0
                gameState.createNoiseEvent(at: gridPosition, level: .medium)
            }
        }
        
        if tent.isEmpty {
            gameState.removeTent(tent)
            targetTent = nil
            requestCloseResource()
        }
    }
    
    private func requestCloseResource() {
        needsCloseResource = true
        collectionTimer = 0
    }
    
    private func updateDynamitePlacement(deltaTime: TimeInterval, gameState: GameState) {
        let rate = calculateCollectionRate()
        collectionTimer += deltaTime * rate
        
        if collectionTimer >= 1.0 {
            collectionTimer -= 1.0
            dynamiteProgress += 1
            noiseAccumulator += 1
            
            if noiseAccumulator >= GameBalance.workshopMediumNoiseThreshold {
                noiseAccumulator = 0
                gameState.createNoiseEvent(at: gridPosition, level: .medium)
            }
            
            if dynamiteProgress >= GameBalance.dynamiteCharges {
                if let bridgeId = linkedBridgeId {
                    gameState.destroyBridge(id: bridgeId)
                    gameState.createNoiseEvent(at: gridPosition, level: .high)
                }
                requestCloseResource()
            }
        }
    }
    
    private func updateDebrisClearing(deltaTime: TimeInterval, gameState: GameState) {
        let rate = calculateCollectionRate()
        collectionTimer += deltaTime * rate
        
        if collectionTimer >= 1.0 {
            collectionTimer -= 1.0
            collectedWood += 1
            noiseAccumulator += 1
            
            if noiseAccumulator >= GameBalance.workshopMediumNoiseThreshold {
                noiseAccumulator = 0
                gameState.createNoiseEvent(at: gridPosition, level: .medium)
            }
        }
        
        if collectedWood >= 20 {
            gameState.map.setTile(at: gridPosition, type: .ground)
            gameState.scene?.refreshTerrain()
            requestCloseResource()
        }
    }
    
    private func updateResourceCollection(from building: CityBuilding, deltaTime: TimeInterval, gameState: GameState) {
        guard building.canBeHarvested else {
            if !building.hasResources && !building.hasZombies {
                requestCloseResource()
            }
            return
        }
        
        let rate = calculateCollectionRate()
        collectionTimer += deltaTime * rate
        
        if collectionTimer >= 1.0 {
            collectionTimer -= 1.0
            collectResource(from: building, gameState: gameState)
        }
    }
    
    private func calculateCollectionRate() -> Double {
        let baseRate: Double = 1.0
        return baseRate * pow(1.35, Double(presentSurvivors - 1))
    }
    
    private func collectResource(from building: CityBuilding, gameState: GameState) {
        let collectWood = building.resources.wood >= building.resources.bullets
        
        if collectWood && building.resources.wood > 0 {
            building.resources.wood -= 1
            collectedWood += 1
        } else if building.resources.bullets > 0 {
            building.resources.bullets -= 1
            collectedBullets += 1
        } else if building.resources.survivors > 0 {
            building.resources.survivors -= 1
            collectedSurvivors += 1
        }
        
        noiseAccumulator += 1
        
        if noiseAccumulator >= GameBalance.workshopMediumNoiseThreshold {
            noiseAccumulator = 0
            gameState.createNoiseEvent(at: gridPosition, level: .medium)
        }
    }
    
    private func updateTruckSpawning(deltaTime: TimeInterval, gameState: GameState) {
        truckSpawnAccumulator += deltaTime
        let spawnInterval = 1.0 / Double(GameBalance.workshopMaxTrucksPerSecond)
        
        while truckSpawnAccumulator >= spawnInterval {
            truckSpawnAccumulator -= spawnInterval
            
            if collectedWood >= GameBalance.truckCapacity && presentSurvivors > 1 {
                spawnTruck(wood: GameBalance.truckCapacity, bullets: 0, gameState: gameState)
                collectedWood -= GameBalance.truckCapacity
            } else if collectedBullets >= GameBalance.truckCapacity && presentSurvivors > 1 {
                spawnTruck(wood: 0, bullets: GameBalance.truckCapacity, gameState: gameState)
                collectedBullets -= GameBalance.truckCapacity
            } else if presentSurvivors == 1 && (collectedWood >= GameBalance.truckCapacity || collectedBullets >= GameBalance.truckCapacity) {
                if collectedWood >= GameBalance.truckCapacity {
                    spawnTruck(wood: GameBalance.truckCapacity, bullets: 0, gameState: gameState, returnToWorkshop: true)
                    collectedWood -= GameBalance.truckCapacity
                } else {
                    spawnTruck(wood: 0, bullets: GameBalance.truckCapacity, gameState: gameState, returnToWorkshop: true)
                    collectedBullets -= GameBalance.truckCapacity
                }
            } else if collectedSurvivors > 0 {
                if let depot = sourceDepot {
                    let survivor = FreeSurvivor(at: gridPosition)
                    survivor.destinationDepot = depot
                    _ = survivor.setDestination(depot.gridPosition, map: gameState.map)
                    gameState.addFreeSurvivor(survivor)
                    collectedSurvivors -= 1
                }
            } else {
                break
            }
        }
    }
    
    private func spawnTruck(wood: Int, bullets: Int, gameState: GameState, returnToWorkshop: Bool = false) {
        guard let depot = sourceDepot else { return }
        
        presentSurvivors -= 1
        
        let truck = Truck(at: gridPosition, sourceDepot: depot)
        truck.carryingWood = wood
        truck.carryingBullets = bullets
        truck.targetBuilding = depot
        truck.isFromWorkshop = true  // Workshop trucks - survivor stays at depot
        truck.returnWorkshop = returnToWorkshop ? self : nil
        _ = truck.setDestination(depot.gridPosition, map: gameState.map)
        gameState.addTruck(truck)
    }
    
    private func finishWorkshop(gameState: GameState) {
        isFinished = true
        
        // Remove debris object if we were collecting from one
        if let debris = targetDebris {
            gameState.map.removeDebrisObject(debris)
            targetDebris = nil
        }
        
        while collectedWood > 0 || collectedBullets > 0 {
            if collectedWood > 0 && presentSurvivors > 0 {
                let amount = min(GameBalance.truckCapacity, collectedWood)
                spawnTruck(wood: amount, bullets: 0, gameState: gameState)
                collectedWood -= amount
            } else if collectedBullets > 0 && presentSurvivors > 0 {
                let amount = min(GameBalance.truckCapacity, collectedBullets)
                spawnTruck(wood: 0, bullets: amount, gameState: gameState)
                collectedBullets -= amount
            } else {
                break
            }
        }
        
        for _ in 0..<presentSurvivors {
            if let depot = sourceDepot {
                let survivor = FreeSurvivor(at: gridPosition)
                survivor.destinationDepot = depot
                _ = survivor.setDestination(depot.gridPosition, map: gameState.map)
                gameState.addFreeSurvivor(survivor)
            }
        }
        presentSurvivors = 0
        
        gameState.removeWorkshop(self)
    }
    
    override func retreat(gameState: GameState) {
        finishWorkshop(gameState: gameState)
    }
    
    func onZombieAttack(zombieCount: Int, gameState: GameState) {
        var survivorsKilled = 0
        for _ in 0..<zombieCount {
            if CGFloat.random(in: 0...1) < GameBalance.workshopSurvivorDeathChance && presentSurvivors > survivorsKilled {
                survivorsKilled += 1
            }
        }
        
        for _ in 0..<survivorsKilled {
            presentSurvivors -= 1
            gameState.spawnZombie(at: gridPosition, type: .normal)
        }
        
        for _ in 0..<presentSurvivors {
            let scatterX = gridPosition.x + Int.random(in: -1...1)
            let scatterY = gridPosition.y + Int.random(in: -1...1)
            let scatterPos = GridPosition(x: scatterX, y: scatterY)
            
            let survivor = FreeSurvivor(at: scatterPos)
            if let depot = sourceDepot {
                survivor.destinationDepot = depot
                _ = survivor.setDestination(depot.gridPosition, map: gameState.map)
            }
            gameState.addFreeSurvivor(survivor)
        }
        presentSurvivors = 0
    }
}

// MARK: - Sniper Tower
class SniperTower: PlayerBuilding {
    var isHoldingFire: Bool = false
    private var fireTimer: TimeInterval = 0
    
    // Construction & Upgrade Tracking
    var constructionWood: Int = 0
    let constructionCost: Int = 20
    var upgradeLevel: Int = 0
    var isUpgradePending: Bool = false
    var currentExtraRange: CGFloat = 0
    
    init() {
        super.init(type: .sniperTower)
        survivorQuota = 1
        bulletQuota = 50
        woodQuota = 20
    }
    
    var accuracy: CGFloat {
        let x = CGFloat(min(presentSurvivors, GameBalance.sniperMaxSurvivors))
        return x / CGFloat(GameBalance.sniperMaxSurvivors)
    }
    
    var canFire: Bool {
        let isBuilt = constructionWood >= constructionCost
        return isBuilt && presentBullets > 0 && !isHoldingFire && presentSurvivors > 0
    }
    
    override func update(deltaTime: TimeInterval, gameState: GameState) {
        super.update(deltaTime: deltaTime, gameState: gameState)
        
        handleExcessInventory(gameState: gameState)
        
        guard canFire else { return }
        
        fireTimer += deltaTime
        if fireTimer >= GameBalance.sniperFireRate {
            fireTimer = 0
            attemptShot(gameState: gameState)
        }
    }
    
    private func attemptShot(gameState: GameState) {
        guard let target = findTarget(gameState: gameState) else { return }
        
        presentBullets -= 1
        gameState.createNoiseEvent(at: gridPosition, level: .high)
        
        let roll = CGFloat.random(in: 0...1)
        let hit = roll <= accuracy
        
        if hit {
            gameState.killZombie(target)
        }
        
        if let scene = node?.scene as? GameScene {
            let from = gridPosition.toScenePosition()
            let to = target.node?.position ?? from
            scene.showSniperShot(from: from, to: to, hit: hit)
        }
    }
    
    private func findTarget(gameState: GameState) -> Zombie? {
        let towerPos = gridPosition.toScenePosition()
        
        let baseRange = CGFloat(GameBalance.sniperRange)
        let totalRangeInBlocks = baseRange + currentExtraRange
        let rangeInPoints = totalRangeInBlocks * GridConfig.tileSize
        
        var closestZombie: Zombie?
        var closestDistance: CGFloat = .infinity
        
        for zombie in gameState.zombies where !zombie.isDead {
            guard let zombieNode = zombie.node else { continue }
            let distance = towerPos.distance(to: zombieNode.position)
            
            if distance <= rangeInPoints && distance < closestDistance {
                closestDistance = distance
                closestZombie = zombie
            }
        }
        return closestZombie
    }

    func addWood(_ amount: Int) {
        if constructionWood < constructionCost {
            constructionWood += amount
            if constructionWood >= constructionCost {
                woodQuota = 0
            }
        } else if isUpgradePending && upgradeLevel < 2 {
            presentWood += amount
            if presentWood >= 20 {
                presentWood -= 20
                upgradeLevel += 1
                currentExtraRange += 8
                isUpgradePending = false
                woodQuota = 0
            }
        }
        updateIndicator()
    }

    private func handleExcessInventory(gameState: GameState) {
        let hasZombiesInRange = findTarget(gameState: gameState) != nil
        
        if presentBullets >= (bulletQuota + 10) && !hasZombiesInRange {
            if presentSurvivors > 0 {
                if let servicer = primaryServicer, !servicer.isDestroyed {
                    sendBulletsToDepot(gameState: gameState, targetDepot: servicer)
                }
            }
        }
    }

    private func sendBulletsToDepot(gameState: GameState, targetDepot: Depot) {
        guard presentSurvivors > 0 else { return }
        
        presentBullets -= 10
        presentSurvivors -= 1
        
        let truck = Truck(at: gridPosition, sourceDepot: targetDepot)
        truck.carryingBullets = 10
        truck.targetBuilding = targetDepot
        _ = truck.setDestination(targetDepot.gridPosition, map: gameState.map)
        gameState.addTruck(truck)
        
        updateIndicator()
    }
    
    func requestUpgrade() {
        guard upgradeLevel < 2 && !isUpgradePending else { return }
        isUpgradePending = true
        woodQuota = 20
    }

    func shootInAir(gameState: GameState) {
        guard presentBullets > 0 else { return }
        presentBullets -= 1
        gameState.createNoiseEvent(at: gridPosition, level: .high)
        
        if let scene = node?.scene as? GameScene {
            let from = gridPosition.toScenePosition()
            let to = CGPoint(x: from.x, y: from.y + 100)
            scene.showSniperShot(from: from, to: to, hit: false)
        }
    }
    
    override func retreat(gameState: GameState) {
        let safetyRange: CGFloat = 8
        let nearest = gameState.findNearestDepot(to: gridPosition, excluding: nil)
        let isSafe = nearest != nil && CGFloat(gridPosition.distance(to: nearest!.gridPosition)) <= safetyRange

        if !isSafe {
            if presentWood > 0 || presentBullets > 0 {
                let dropped = gameState.map.dropResources(at: gridPosition, wood: presentWood, bullets: presentBullets)
                gameState.addDroppedResource(dropped)
            }
            presentSurvivors = 0
        } else {
            for _ in 0..<presentSurvivors {
                if let depot = nearest {
                    let survivor = FreeSurvivor(at: gridPosition)
                    survivor.destinationDepot = depot
                    _ = survivor.setDestination(depot.gridPosition, map: gameState.map)
                    gameState.addFreeSurvivor(survivor)
                }
            }
        }
        
        presentSurvivors = 0
        presentBullets = 0
        presentWood = 0
    }
}

// MARK: - Barricade
class Barricade: PlayerBuilding {
    init() {
        super.init(type: .barricade)
    }
    
    var health: Int { presentWood }
    override var isDestroyed: Bool { presentWood <= 0 && woodQuota <= 0 }
    
    override func takeDamage(_ amount: Int) {
        presentWood = max(0, presentWood - amount)
        updateVisual()
    }
    
    private func updateVisual() {
        guard let shapeNode = node as? SKShapeNode else { return }
        
        let maxHealth = max(woodQuota, 1)
        let healthPercent = CGFloat(presentWood) / CGFloat(maxHealth)
        
        let red = 0.7 + (1.0 - healthPercent) * 0.3
        let green = 0.5 * healthPercent
        let blue = 0.3 * healthPercent
        
        shapeNode.fillColor = SKColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    override func retreat(gameState: GameState) {
        woodQuota = 0
    }
}
