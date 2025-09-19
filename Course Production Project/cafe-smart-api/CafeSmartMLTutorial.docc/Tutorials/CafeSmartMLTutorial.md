# CafeSmart ML: Business Intelligence & Feature Engineering

Learn how business operations drive data collection and feature engineering decisions in machine learning systems.

## Overview

This tutorial teaches you how to understand the relationship between business operations and machine learning feature engineering. You'll learn how cafe operations create data patterns, why specific features improve predictions, and how business logic translates to ML features.

## Learning Objectives

By the end of this tutorial, you will be able to:

- Understand how cafe operations create data patterns
- Identify business-driven features for ML models
- Map business questions to data needs
- Design feature engineering pipelines
- Explain why domain knowledge drives ML success

## Prerequisites

- Basic understanding of machine learning concepts
- Familiarity with data analysis
- Interest in business intelligence and feature engineering

---

## Understanding the Cafe Business Model

The foundation of any successful ML system is understanding the business it serves. Let's explore how cafe operations create the data patterns that drive our machine learning models.

### Business Operations Flow

A cafe's daily operations follow a predictable pattern:

```
Customer Orders → Menu Items → Recipe Components → Inventory Items → Supplier Orders
```

**Daily Operations:**
- Peak Hours: 7-9am, 12-2pm
- Weekend vs Weekday Patterns  
- Seasonal Trends

**Business Goals:**
- Minimize Waste
- Maximize Freshness
- Optimize Inventory Costs
- Ensure Customer Satisfaction

### Key Business Challenges

| Challenge | Impact | Data Needed |
|-----------|--------|-------------|
| Inventory Waste | 15-20% of ingredients discarded | Usage patterns, shelf life |
| Stockouts | Lost sales, customer dissatisfaction | Demand forecasting, lead times |
| Over-ordering | Increased costs, storage issues | Accurate demand prediction |
| Peak Demand | Service delays, quality issues | Temporal patterns, capacity planning |

---

## Data Collection Strategy

Understanding why we collect specific data is crucial for building effective ML models.

### Business Question to Data Mapping

Every piece of data we collect should answer a specific business question:

```
Business Question → Data Need → Feature Engineering → ML Prediction
```

**Specific Mappings:**

- **"When will we run out?"** → Historical usage patterns → `usage_lag_1d`, `usage_lag_7d`
- **"What affects demand?"** → Temporal patterns → `day`, `weekday`, `month`, `year`  
- **"How much to order?"** → Order volume patterns → `orders_total_lag_1d`, `items_total_lag_1d`
- **"What's the trend?"** → Rolling averages → `rolling_usage_last_7d`
- **"Seasonal patterns?"** → Long-term patterns → `usage_same_weekday_lag_28d`

---

## Recipe-to-Ingredient Mapping

Understanding how customer orders translate to ingredient usage is essential for accurate predictions.

### Data Transformation Process

```
Customer Order → Menu Item Selection → Recipe Lookup → Ingredient Requirements → Inventory Consumption
```

**Example Flow:**
```
Order: 2 Lattes + 1 Croissant
├── Menu Items: COFFEE-001, COFFEE-001, CROISSANT-001
├── Recipes: Latte Recipe, Croissant Recipe
├── Ingredients: 18g beans × 2, 200ml milk × 2, 1 croissant dough
└── Final Usage: BEANS-ESP-1KG: 36g, DAIRY-MILK-1L: 400ml, BAKERY-DOUGH-CROIS: 1 unit
```

**Wastage Calculation:**
- 5% milk spillage → 400ml + 20ml = 420ml
- Additional 10% buffer → 462ml total

### Recipe Component Structure

```json
{
  "menuItemId": "COFFEE-001",
  "name": "Latte",
  "components": [
    {
      "sku": "BEANS-ESP-1KG",
      "unitsPerItem": 0.018,
      "wastageRate": 0.02
    },
    {
      "sku": "DAIRY-MILK-1L", 
      "unitsPerItem": 0.2,
      "wastageRate": 0.05
    }
  ]
}
```

---

## Feature Engineering Breakdown

Feature engineering transforms raw data into meaningful inputs for ML models. Let's explore the different types of features we use.

### Temporal Features

Temporal features capture time-based patterns in business operations:

```
Temporal Features:
├── Day of Month → Payday patterns (1st, 15th, 30th)
├── Weekday → Monday blues, Friday rush
├── Month → Seasonal trends (Summer vs Winter)
├── Year → Year-over-year growth
└── Is Weekend → Weekend vs weekday (different customer base)
```

**Business Logic:**
- **Day of Month**: Payday effects, monthly budget cycles
- **Weekday**: Commuter patterns, office vs residential areas
- **Month**: Seasonal beverages, weather impact
- **Year**: Business growth, market expansion
- **Is Weekend**: Different customer demographics, longer dwell times

### Lag Features

Lag features capture historical patterns that influence future demand:

```
Today's Prediction:
├── Yesterday's Usage → Immediate trends, recent events
├── Last Week's Usage → Weekly patterns, business cycles
└── Last Month's Usage → Seasonal patterns, long-term trends

Rolling Averages:
7-day moving average → Smooths daily variations
```

**Why These Lags Matter:**

| Feature | Business Reason | Example Impact |
|---------|----------------|----------------|
| `usage_lag_1d` | Immediate demand continuity | Yesterday's weather affects today |
| `usage_lag_7d` | Weekly business cycles | Same day last week patterns |
| `usage_lag_28d` | Monthly patterns | Payday cycles, monthly budgets |
| `rolling_usage_last_7d` | Trend smoothing | Reduces noise from daily variations |

### Volume Features

Volume features capture customer behavior patterns:

```
Order Volume Features:
├── orders_total_lag_1d → Number of transactions, customer count
└── items_total_lag_1d → Total items sold, average order size

Business Insights:
├── Customer behavior
├── Operational efficiency
└── Staffing needs
```

**Business Logic:**
- **orders_total_lag_1d**: Customer traffic patterns, marketing effectiveness
- **items_total_lag_1d**: Average order size, menu popularity

---

## Target Variable: `target_usage`

Understanding what we're predicting and why is crucial for model success.

### Why We Predict Usage, Not Sales

```
Business Goal → Inventory Management:
├── Prevent Stockouts
└── Minimize Waste

Prediction Target → Usage Prediction:
├── Ingredient Consumption
└── Inventory Planning

Why Not Sales? → Sales ≠ Usage:
├── Recipe variations
├── Wastage factors
└── Staff training differences
```

**Key Insight**: We predict **ingredient usage**, not **menu item sales**, because:
- Different staff members use different amounts of ingredients
- Wastage rates vary by day, staff, and conditions
- Recipe adherence varies
- Actual consumption drives inventory decisions

### CSV Structure

```csv
sku,date,year,month,day,weekday,is_weekend,orders_total_lag_1d,items_total_lag_1d,usage_lag_1d,usage_lag_7d,rolling_usage_last_7d,usage_same_weekday_lag_28d,target_usage
BEANS-ESP-1KG,2025-09-01,2025,9,1,2,false,45,127,8.5,7.2,7.8,6.9,8.2
```

### Feature Categories

| Category | Features | Business Purpose |
|----------|----------|------------------|
| **Identification** | `sku`, `date` | Data organization, filtering |
| **Temporal** | `year`, `month`, `day`, `weekday`, `is_weekend` | Seasonal patterns, business cycles |
| **Volume** | `orders_total_lag_1d`, `items_total_lag_1d` | Customer traffic, order patterns |
| **Usage History** | `usage_lag_1d`, `usage_lag_7d`, `usage_same_weekday_lag_28d` | Demand patterns, trends |
| **Trends** | `rolling_usage_last_7d` | Smoothed demand patterns |
| **Target** | `target_usage` | What we're trying to predict |

---

## Pattern Recognition

Identifying patterns in data is essential for understanding business operations and improving predictions.

### Data Patterns

```
Data Patterns:
├── Daily Patterns:
│   ├── Morning rush (7-9am peak)
│   ├── Lunch rush (12-2pm peak)
│   └── Afternoon lull (2-5pm quiet)
├── Weekly Patterns:
│   ├── Monday: Low (Post-weekend)
│   ├── Friday: High (Weekend prep)
│   └── Weekend: Different (Leisure customers)
├── Monthly Patterns:
│   ├── Payday effects (1st & 15th)
│   └── Month-end (Budget constraints)
└── Seasonal Patterns:
    ├── Summer: Iced drinks
    ├── Winter: Hot drinks
    └── Holiday seasons (Special events)
```

### Business Intelligence Insights

Understanding these patterns helps you:

- **Optimize staffing**: Schedule more staff during peak hours
- **Manage inventory**: Order more ingredients before busy periods
- **Plan marketing**: Target promotions during slow periods
- **Improve customer experience**: Prepare for high-demand times

---

## Decision-Making Process

Machine learning predictions drive business decisions. Understanding this process is crucial for model success.

### Business Decision Flow

```
Historical Data → Feature Engineering → ML Model Training → Prediction Generation → Business Decision
```

**Business Decision Components:**
- **Reorder Point Calculation**: ROP = Safety Stock + Lead Time Demand
- **Order Quantity**: Order Qty = Par Level - Current Stock
- **Safety Stock**: Safety Stock = Max(Reorder Threshold, Historical Variance)

### Key Differences: Sales vs Usage

| Aspect | Sales Data | Usage Data |
|--------|------------|------------|
| **What it measures** | Menu item orders | Actual ingredient consumption |
| **Accuracy** | Precise order counts | Includes wastage, spillage |
| **Business value** | Revenue tracking | Inventory planning |
| **ML relevance** | Menu optimization | Stock management |

---

## Key Takeaways

### What You Should Understand

| Learning Area | Key Understanding | Business Impact |
|---------------|-------------------|-----------------|
| **Business Context** | How cafe operations create data patterns | Better feature selection |
| **Feature Selection** | Why specific features improve prediction accuracy | More accurate models |
| **Data Quality** | How business processes affect data reliability | Trustworthy predictions |
| **Model Interpretability** | How features relate to business decisions | Actionable insights |
| **Continuous Improvement** | How feedback loops improve predictions | Ongoing optimization |

### Key Insights

| Insight | Why It Matters | Application |
|---------|----------------|-------------|
| **Data reflects business reality** | Every feature has a business justification | Better feature engineering |
| **Temporal patterns matter** | Time-based features capture business cycles | Improved predictions |
| **Volume ≠ Usage** | Understanding the difference is crucial for inventory management | Accurate stock planning |
| **Feature engineering is domain-specific** | Different businesses need different features | Customized solutions |
| **Business logic drives ML success** | Understanding the domain improves model performance | Higher ROI |

---

## Next Steps

Now that you understand the relationship between business operations and machine learning, you can:

1. **Apply these concepts** to your own business domain
2. **Design feature engineering pipelines** based on business understanding
3. **Build interpretable ML models** that drive actionable business decisions
4. **Continuously improve** your models based on business feedback

### Further Learning

- **Inventory Management**: EOQ models, safety stock calculations
- **Time Series Analysis**: ARIMA, seasonal decomposition
- **Feature Engineering**: Domain-specific feature creation
- **Business Intelligence**: Converting data into actionable insights

---

## 🎯 **Practical Exercises**

### **Exercise 1: Business Question Mapping**
Map these business questions to the data features you would need:

**Business Questions:**
- "Should we increase our coffee bean order for next week?"
- "What's the best time to schedule staff training?"
- "How much milk should we order for the weekend?"

**Your Task:** For each question, identify:
1. What data you need to collect
2. What features you would engineer
3. What the prediction target would be

### **Exercise 2: Feature Engineering Practice**
Given this raw data, create meaningful features:

**Raw Data:**
```csv
date,orders,milk_used,coffee_used
2025-09-01,45,12.5,8.2
2025-09-02,38,10.8,7.1
2025-09-03,52,14.2,9.3
```

**Your Task:** Create temporal and lag features that would help predict tomorrow's ingredient usage.

### **Exercise 3: Real-World Scenario**
You're managing a cafe chain with 5 locations. Each location has different customer patterns:

- **Location A**: Office district, busy weekdays, quiet weekends
- **Location B**: Tourist area, busy weekends, seasonal variations
- **Location C**: University area, busy during semesters, quiet during breaks

**Your Task:** Design a feature engineering strategy that accounts for these location differences.

## 🧠 **Check Your Understanding**

### **Knowledge Questions:**
1. Why do we predict ingredient usage instead of menu item sales?
2. How do temporal features capture business patterns?
3. What's the difference between lag features and rolling averages?
4. How does understanding business operations improve feature engineering?
5. Why is it important to understand the data transformation from orders to usage?

### **Application Questions:**
6. **Scenario**: Your cafe's coffee bean usage has been inconsistent. Yesterday you used 8.5kg, last week same day you used 7.2kg, and the 7-day average is 7.8kg. What factors would you consider for tomorrow's prediction?

7. **Decision Making**: You have 15kg of coffee beans in stock. Your model predicts 8.2kg usage tomorrow with 85% confidence. Your supplier takes 3 days to deliver. Should you reorder? Why?

8. **Feature Selection**: You're building a model for a new cafe location. What historical data would you need from similar locations to make accurate predictions?

## 🚀 **Next Steps: Apply Your Learning**

### **Immediate Actions:**
1. **Analyze Your Data**: Look at your cafe's order patterns and identify temporal trends
2. **Map Business Questions**: List 5 business questions your cafe faces daily
3. **Design Features**: For each question, design the features you'd need
4. **Test Understanding**: Try to predict next week's coffee bean usage using only historical data

### **Advanced Challenges:**
1. **Multi-Location Model**: Design a feature engineering strategy for a cafe chain
2. **Seasonal Adjustments**: How would you handle holiday seasons and special events?
3. **External Factors**: What external data (weather, events, holidays) would improve predictions?

## 📚 **Further Learning Resources**

### **Recommended Reading:**
- **"Feature Engineering for Machine Learning"** by Alice Zheng
- **"Business Intelligence Guide"** - Understanding data-driven decision making
- **"Time Series Analysis"** - Advanced temporal pattern recognition

### **Hands-On Practice:**
- **Kaggle Competitions**: Practice feature engineering on real datasets
- **Your Own Data**: Apply these concepts to your personal projects
- **Open Datasets**: Explore retail and restaurant datasets

---

## 🎓 **Learning Outcomes Verification**

**By completing this tutorial, you should be able to:**

✅ **Explain** why business understanding drives ML success  
✅ **Identify** business questions that ML can solve  
✅ **Design** feature engineering pipelines based on business logic  
✅ **Map** business operations to data collection needs  
✅ **Apply** temporal and lag features to time series problems  
✅ **Understand** the difference between sales data and usage data  
✅ **Create** interpretable ML models that drive business decisions  

**If you can confidently answer all the questions above and complete the exercises, you've mastered the fundamentals of business-driven machine learning!**

---

*This tutorial provides the foundation for understanding how business operations drive data collection and feature engineering decisions in ML systems. The practical exercises ensure you can apply these concepts to real-world scenarios.*
