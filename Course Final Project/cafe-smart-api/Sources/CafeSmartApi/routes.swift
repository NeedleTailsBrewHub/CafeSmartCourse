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
    let predictorController = CafePredictorController()
    
    // Users
    apiRoute.post("register", use: userController.register)
    apiRoute.post("login", use: userController.login)
    userProtected.post("logout", use: userController.logout)
    
    // Orders
    userProtected.post("orders", use: orderController.create)
    adminProtected.get("orders", use: orderController.list)
    adminProtected.get("orders", ":id", use: orderController.get)
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
    adminProtected.on(
        .POST, "predictor", "models", "upload",
        body: .collect(maxSize: "200mb"),
        use: predictorController.uploadModel(req:))
    adminProtected.get("predictor", "models", use: predictorController.listModels(req:))
    adminProtected.post("predictor", "models", "activate", use: predictorController.activateModel(req:))
    adminProtected.post("predictor", "models", "delete", use: predictorController.deleteModel(req:))
    adminProtected.post("predictor", "instantiate", use: predictorController.instantiatePredictor(req:))
    adminProtected.post("predictor", "restock", "decide", use: predictorController.decideRestock(req:))
    adminProtected.get("predictor", "capabilities", use: predictorController.capabilities(req:))
    adminProtected.post("predictor", "train", use: predictorController.startTrain(req:))
    adminProtected.get("predictor", "train", use: predictorController.listTrainJobs(req:))
    adminProtected.get("predictor", "train", ":jobId", use: predictorController.getTrainJob(req:))

    // Realtime WebSockets are served by ConnectionManagerKit on WS_PORT (default 8081).
}
