import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  String _userName = 'User';
  double _dailyCalorieBudget = 2000;
  String _goal = 'Maintain Weight';

  Map<String, List<Map<String, dynamic>>> meals = {
    'Breakfast': [],
    'Morning Snacks': [],
    'Lunch': [],
    'Evening Snacks': [],
    'Dinner': [],
  };

  int get totalCalories {
    int total = 0;
    meals.forEach((_, items) {
      for (var item in items) {
        total += item['calories'] as int;
      }
    });
    return total;
  }

  void logout(BuildContext context) async {
    await _auth.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> loadMealsFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .orderBy('timestamp', descending: true)
        .get();

    Map<String, List<Map<String, dynamic>>> fetchedMeals = {
      'Breakfast': [],
      'Morning Snacks': [],
      'Lunch': [],
      'Evening Snacks': [],
      'Dinner': [],
    };

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final mealType = data['type'];
      if (mealType != null && fetchedMeals.containsKey(mealType)) {
        fetchedMeals[mealType]?.add({
          'docId': doc.id,
          'food': data['food'],
          'calories': data['calories'],
          'type': mealType,
        });
      }
    }

    setState(() {
      meals = fetchedMeals;
    });
  }

  Future<void> deleteMeal(String docId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(docId)
        .delete();

    await loadMealsFromFirestore();
  }

  void navigateToAddMeal({Map<String, dynamic>? mealToEdit}) async {
    final result =
        await Navigator.pushNamed(context, '/addMeal', arguments: mealToEdit);

    if (result != null && result is Map<String, dynamic>) {
      await loadMealsFromFirestore();
    }
  }

  Widget buildMealSection(String mealType) {
    final items = meals[mealType] ?? [];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: ExpansionTile(
        title: Text(
          mealType,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0),
          ),
        ),
        leading: Icon(
          _getMealTypeIcon(mealType),
          color: Color(0xFF2196F3),
        ),
        childrenPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: items.isEmpty
            ? [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "No items added.",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              ]
            : items.map((item) {
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      item['food'],
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Color(0xFF2196F3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            "${item['calories']} kcal",
                            style: TextStyle(
                              color: Color(0xFF1565C0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                          onSelected: (value) async {
                            if (value == 'edit') {
                              navigateToAddMeal(mealToEdit: item);
                            } else if (value == 'delete') {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Delete Meal'),
                                  content: Text(
                                    'Are you sure you want to delete this meal?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: Text(
                                        'Delete',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await deleteMeal(item['docId']);
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 20),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
      ),
    );
  }

  IconData _getMealTypeIcon(String mealType) {
    switch (mealType) {
      case 'Breakfast':
        return Icons.breakfast_dining;
      case 'Morning Snacks':
        return Icons.coffee;
      case 'Lunch':
        return Icons.lunch_dining;
      case 'Evening Snacks':
        return Icons.cookie;
      case 'Dinner':
        return Icons.dinner_dining;
      default:
        return Icons.restaurant;
    }
  }

  @override
  void initState() {
    super.initState();
    loadMealsFromFirestore();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _userName = data['name'] ?? 'User';
        _dailyCalorieBudget = (data['dailyCalories'] ?? 2000).toDouble();
        _goal = data['goal'] ?? 'Maintain Weight';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Dashboard"),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () async {
              await Navigator.pushNamed(context, '/profile');
              _loadUserProfile();
              loadMealsFromFirestore();
            },
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Welcome, $_userName",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          color: Color(0xFF2196F3),
                          size: 32,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Calories Today",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    "$totalCalories",
                                    style: TextStyle(
                                      color: Color(0xFF1565C0),
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    " / ${_dailyCalorieBudget.round()} kcal",
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Goal: ${_goal}",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (totalCalories / _dailyCalorieBudget).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          totalCalories < _dailyCalorieBudget
                              ? Color(0xFF2196F3)
                              : Colors.red,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${((totalCalories / _dailyCalorieBudget) * 100).round()}% of daily goal",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          "${(_dailyCalorieBudget - totalCalories).round()} kcal remaining",
                          style: TextStyle(
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Meal Summary",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.add, size: 20),
                  label: Text("Add Meal"),
                  onPressed: () => navigateToAddMeal(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            buildMealSection("Breakfast"),
            buildMealSection("Morning Snacks"),
            buildMealSection("Lunch"),
            buildMealSection("Evening Snacks"),
            buildMealSection("Dinner"),
          ],
        ),
      ),
    );
  }
}
