import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FoodItem {
  final String name;
  final double calories;
  final String photoUrl;
  final double servingQuantity;
  final String servingUnit;
  final Map<String, double> nutrients;

  FoodItem({
    required this.name,
    required this.calories,
    required this.photoUrl,
    required this.servingQuantity,
    required this.servingUnit,
    required this.nutrients,
  });
}

class AddMealPage extends StatefulWidget {
  const AddMealPage({Key? key}) : super(key: key);

  @override
  _AddMealPageState createState() => _AddMealPageState();
}

class _AddMealPageState extends State<AddMealPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();

  String? _food;
  double? _calories;
  double _quantity = 100;
  String _mealType = 'Breakfast';
  String? _docId;
  List<FoodItem> _searchResults = [];
  bool _isLoading = false;
  FoodItem? _selectedFood;
  int _waterGlasses = 0;
  String? _waterDocId;

  // Nutritionix API credentials - these are available for free
  final String _appId = '4e24a7c5'; // This is a demo app ID
  final String _appKey =
      '0c3c84e82a4f17d3e10c9232a8f8c168'; // This is a demo app key

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadTodayWaterIntake();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (args != null) {
      _food = args['food'];
      _calories = args['calories'].toDouble();
      _mealType = args['type'] ?? 'Breakfast';
      _docId = args['docId'];
      _waterGlasses = args['waterGlasses'] ?? 0;
      _searchController.text = _food ?? '';
    }
  }

  Future<void> _onSearchChanged() async {
    if (_searchController.text.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await searchFood(_searchController.text);
      setState(() => _searchResults = results);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<FoodItem>> searchFood(String query) async {
    final url = Uri.parse('https://trackapi.nutritionix.com/v2/search/instant');

    try {
      final response = await http.post(
        url,
        headers: {
          'x-app-id': 'd46ec2e2',
          'x-app-key': '60efa9746791e93dbf0a7e133547cee1',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'query': query,
          'detailed': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final commonFoods = data['common'] as List;
        final brandedFoods = data['branded'] as List;

        List<FoodItem> foods = [];

        // Process common foods
        for (var item in commonFoods) {
          foods.add(FoodItem(
            name: item['food_name'],
            calories: item['full_nutrients']
                    ?.firstWhere(
                      (n) => n['attr_id'] == 208,
                      orElse: () => {'value': 0},
                    )['value']
                    ?.toDouble() ??
                0,
            photoUrl: item['photo']['thumb'] ?? '',
            servingQuantity: item['serving_qty']?.toDouble() ?? 100,
            servingUnit: item['serving_unit'] ?? 'g',
            nutrients: {
              'protein': item['full_nutrients']
                      ?.firstWhere(
                        (n) => n['attr_id'] == 203,
                        orElse: () => {'value': 0},
                      )['value']
                      ?.toDouble() ??
                  0,
              'fat': item['full_nutrients']
                      ?.firstWhere(
                        (n) => n['attr_id'] == 204,
                        orElse: () => {'value': 0},
                      )['value']
                      ?.toDouble() ??
                  0,
              'carbs': item['full_nutrients']
                      ?.firstWhere(
                        (n) => n['attr_id'] == 205,
                        orElse: () => {'value': 0},
                      )['value']
                      ?.toDouble() ??
                  0,
              'fiber': item['full_nutrients']
                      ?.firstWhere(
                        (n) => n['attr_id'] == 291,
                        orElse: () => {'value': 0},
                      )['value']
                      ?.toDouble() ??
                  0,
            },
          ));
        }

        // Process branded foods
        for (var item in brandedFoods) {
          foods.add(FoodItem(
            name: '${item['food_name']} (${item['brand_name']})',
            calories: item['nf_calories']?.toDouble() ?? 0,
            photoUrl: item['photo']['thumb'] ?? '',
            servingQuantity: item['serving_qty']?.toDouble() ?? 100,
            servingUnit: item['serving_unit'] ?? 'g',
            nutrients: {
              'protein': item['nf_protein']?.toDouble() ?? 0,
              'fat': item['nf_total_fat']?.toDouble() ?? 0,
              'carbs': item['nf_total_carbohydrate']?.toDouble() ?? 0,
              'fiber': item['nf_dietary_fiber']?.toDouble() ?? 0,
            },
          ));
        }

        return foods.take(10).toList();
      }
    } catch (e) {
      print("Error searching food: $e");
    }
    return [];
  }

  void _selectFood(FoodItem food) {
    setState(() {
      _selectedFood = food;
      _food = food.name;
      _calories = food.calories;
      _searchResults = [];
      _searchController.text = food.name;
      _quantity = food.servingQuantity;
    });
  }

  String _getTodayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTodayWaterIntake() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final today = _getTodayDate();
    
    try {
      final waterDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('water_intake')
          .doc(today)
          .get();

      if (waterDoc.exists) {
        setState(() {
          _waterGlasses = waterDoc.data()?['glasses'] ?? 0;
          _waterDocId = waterDoc.id;
        });
      } else {
        _waterDocId = today;
      }
    } catch (e) {
      print('Error loading water intake: $e');
    }
  }

  Future<void> _incrementWater() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _waterGlasses++;
    });

    await _updateWaterIntake();
  }

  Future<void> _decrementWater() async {
    if (_waterGlasses <= 0) return;
    
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _waterGlasses--;
    });

    await _updateWaterIntake();
  }

  Future<void> _updateWaterIntake() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('water_intake')
          .doc(_waterDocId ?? _getTodayDate())
          .set({
        'glasses': _waterGlasses,
        'date': _getTodayDate(),
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating water intake: $e');
    }
  }

  void saveMeal() async {
    if (!_formKey.currentState!.validate() || _selectedFood == null) return;

    _formKey.currentState!.save();
    final user = _auth.currentUser;
    if (user == null) return;

    final actualCalories =
        (_quantity / _selectedFood!.servingQuantity) * _selectedFood!.calories;

    final mealData = {
      'food': _food,
      'calories': actualCalories.round(),
      'quantity': _quantity,
      'unit': _selectedFood!.servingUnit,
      'type': _mealType,
      'nutrients': _selectedFood!.nutrients,
      'date': _getTodayDate(),
      'timestamp': FieldValue.serverTimestamp(),
    };

    DocumentReference docRef;
    if (_docId != null) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .doc(_docId)
          .update(mealData);
      docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .doc(_docId!);
    } else {
      docRef = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .add(mealData);
    }

    Navigator.pop(context, {
      'docId': docRef.id,
      'food': _food,
      'calories': actualCalories.round(),
      'type': _mealType,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_docId == null ? 'Add Meal' : 'Edit Meal')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2196F3).withOpacity(0.1),
              Colors.white,
            ],
            stops: [0.0, 0.3],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search Food',
                          style: TextStyle(
                            color: Color(0xFF1565C0),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Food Name',
                            hintText: 'Search for food items...',
                            prefixIcon: Icon(Icons.search),
                            suffixIcon: _isLoading
                                ? Padding(
                                    padding: EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Select a food item'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Expanded(
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final food = _searchResults[index];
                          return ListTile(
                            leading: food.photoUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      food.photoUrl,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Color(0xFF2196F3).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.restaurant,
                                      color: Color(0xFF2196F3),
                                    ),
                                  ),
                            title: Text(food.name),
                            subtitle: Text(
                              '${food.calories.round()} kcal per ${food.servingQuantity} ${food.servingUnit}',
                            ),
                            onTap: () => _selectFood(food),
                          );
                        },
                      ),
                    ),
                  ),
                if (_selectedFood != null) ...[
                  SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quantity',
                            style: TextStyle(
                              color: Color(0xFF1565C0),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: _quantity.toString(),
                                  decoration: InputDecoration(
                                    labelText:
                                        'Quantity (${_selectedFood!.servingUnit})',
                                    prefixIcon: Icon(Icons.scale),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    final parsed = double.tryParse(value ?? '');
                                    if (parsed == null || parsed <= 0)
                                      return 'Enter a valid quantity';
                                    return null;
                                  },
                                  onChanged: (value) {
                                    setState(() {
                                      _quantity =
                                          double.tryParse(value) ?? _quantity;
                                    });
                                  },
                                ),
                              ),
                              SizedBox(width: 16),
                              Column(
                                children: [
                                  Text(
                                    'Calories',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  Text(
                                    '${((_quantity / _selectedFood!.servingQuantity) * _selectedFood!.calories).round()}',
                                    style: TextStyle(
                                      color: Color(0xFF1565C0),
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'kcal',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meal Type',
                            style: TextStyle(
                              color: Color(0xFF1565C0),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _mealType,
                            decoration: InputDecoration(
                              prefixIcon: Icon(Icons.restaurant_menu),
                            ),
                            items: [
                              'Breakfast',
                              'Morning Snacks',
                              'Lunch',
                              'Evening Snacks',
                              'Dinner',
                            ]
                                .map((e) =>
                                    DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _mealType = value!),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 24),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.local_drink,
                                  color: Color(0xFF1565C0),
                                  size: 24,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Water Intake',
                                  style: TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Today',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _decrementWater,
                              icon: Icon(Icons.remove_circle),
                              color: Color(0xFF1565C0),
                              iconSize: 32,
                            ),
                            SizedBox(width: 16),
                            Column(
                              children: [
                                Text(
                                  '$_waterGlasses',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                                Text(
                                  'glasses',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(width: 16),
                            IconButton(
                              onPressed: _incrementWater,
                              icon: Icon(Icons.add_circle),
                              color: Color(0xFF1565C0),
                              iconSize: 32,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                if (_selectedFood != null)
                  ElevatedButton(
                    onPressed: saveMeal,
                    child: Text(_docId == null ? 'Add Meal' : 'Update Meal'),
                    style: ElevatedButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
