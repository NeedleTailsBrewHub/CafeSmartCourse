import Vapor

func routes(_ app: Application) throws {
    
    let apiRoute = app.grouped("api")
    let authRoute = apiRoute.grouped("auth")
    let userProtected = authRoute.grouped(AuthenticationMiddleware())
    let adminProtected = userProtected.grouped(AdminMiddleware())
    
    let userController = UserController()
    let orderController = OrderController()
    let inventoryController = InventoryController()
    let recipeController = RecipeController()
    let menuController = MenuController()
    #if canImport(CoreML)
    let predictorController = CafePredictorController()
    
    // Users
    // https://localhost:8080/api/auth/some-endpoint
    // https://localhost:8080/api/register
    apiRoute.post("register", use: userController.register)
    apiRoute.post("login", use: userController.login)
    userProtected.post("logout", use: userController.logout)
    
    // Orders
    userProtected.post("orders", use: orderController.create)
//    userProtected.get("orders", ":email" use: orderController.filteredList)
    adminProtected.get("orders", use: orderController.list)
    adminProtected.get("orders", ":id", use: orderController.get) //http://locahost:8080/api/auth/orders/some-uuid
    adminProtected.put("orders", ":id", "status", use: orderController.updateStatus)
    adminProtected.delete("orders", ":id", use: orderController.delete)
    
    // Inventory
    adminProtected.get("inventory", use: inventoryController.list(req:))
    adminProtected.get("inventory", ":id", use: inventoryController.get(req:))
    adminProtected.post("inventory", use: inventoryController.create(req:))
    adminProtected.put("inventory", ":id", use: inventoryController.update(req:))
    adminProtected.delete("inventory", ":id", use: inventoryController.delete(req:))
    
    // Recipes
    adminProtected.get("recipes", use: recipeController.list(req:))
    adminProtected.post("recipes", use: recipeController.create(req:))
    adminProtected.get("recipes", ":id", use: recipeController.get(req:))
    adminProtected.put("recipes", ":id", use: recipeController.update(req:))
    adminProtected.delete("recipes", ":id", use: recipeController.delete(req:))
    adminProtected.get("menu", ":id", "recipes", use: recipeController.listForMenuItem(req:))
    
    // Menu
    userProtected.get("menu", use: menuController.list(req:))
    userProtected.get("menu", ":id", use: menuController.get(req:))
    adminProtected.post("menu", use: menuController.create(req:))
    adminProtected.put("menu", ":id", use: menuController.update(req:))
    adminProtected.delete("menu", ":id", use: menuController.delete(req:))
    
    // Predictor
    adminProtected.get("predictor", "export", use: predictorController.exportCSV(req:))
    adminProtected.post("predictor", "models", "upload", use: predictorController.uploadModel(req:))
    #endif
    
//    ws://localhost:8080/api/auth/ws/merchant
    adminProtected.webSocket("ws", "merchant") { req, websocket in
        await app.realtimeHub.subscribe(topic: .merchant, ws: websocket)
    }
    
}
