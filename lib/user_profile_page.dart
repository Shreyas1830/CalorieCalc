import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class CalorieCalculator {
  static double harrisBenedictBMR(double weight, double height, int age, String gender) {
    if (gender == 'Male') {
      return 66.47 + (13.75 * weight) + (5.003 * height) - (6.755 * age);
    } else {
      return 655.1 + (9.563 * weight) + (1.850 * height) - (4.676 * age);
    }
  }

  static double mifflinStJeorBMR(double weight, double height, int age, String gender) {
    if (gender == 'Male') {
      return (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      return (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }
  }

  static double katchMcArdleBMR(double weight, double bodyFat) {
    double leanMass = weight * (1 - (bodyFat / 100));
    return 370 + (21.6 * leanMass);
  }

  static double getActivityMultiplier(int activityLevel) {
    switch (activityLevel) {
      case 1: return 1.2;  // Sedentary
      case 2: return 1.375;  // Lightly active
      case 3: return 1.55;  // Moderately active
      case 4: return 1.725;  // Very active
      default: return 1.2;
    }
  }

  static double calculateCalorieBudget(
    double weight,
    double height,
    int age,
    String gender,
    int activityLevel,
    String goal,
  ) {
    // Calculate BMR using both formulas
    double bmr1 = harrisBenedictBMR(weight, height, age, gender);
    double bmr2 = mifflinStJeorBMR(weight, height, age, gender);
    
    // Average the BMRs
    double averageBMR = (bmr1 + bmr2) / 2;
    
    // Apply activity multiplier
    double tdee = averageBMR * getActivityMultiplier(activityLevel);
    
    // Adjust based on goal
    switch (goal) {
      case 'Weight Loss':
        return tdee - 500; // Create a 500 calorie deficit
      case 'Weight Gain':
        return tdee + 500; // Create a 500 calorie surplus
      default:
        return tdee; // Maintain weight
    }
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({Key? key}) : super(key: key);

  @override
  _UserProfilePageState createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _name;
  String _gender = 'Male';
  int? _age;
  int _activityLevel = 1;
  double? _height;
  double? _weight;
  String _goal = 'Maintain Weight';
  bool _isLoading = true;
  double? _calculatedCalories;

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        setState(() {
          _name = data['name'];
          _gender = data['gender'] ?? 'Male';
          _age = data['age'];
          _activityLevel = data['activityLevel'] ?? 1;
          _height = data['height']?.toDouble();
          _weight = data['weight']?.toDouble();
          _goal = data['goal'] ?? 'Maintain Weight';
          _calculatedCalories = data['dailyCalories']?.toDouble();

          _nameController.text = _name ?? '';
          _ageController.text = _age?.toString() ?? '';
          _heightController.text = _height?.toString() ?? '';
          _weightController.text = _weight?.toString() ?? '';
        });

        // Calculate calories if not already set
        if (_calculatedCalories == null && _weight != null && _height != null && _age != null) {
          await _calculateAndSaveCalories();
        }
      }
    } catch (e) {
      print('Error loading user profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateAndSaveCalories() async {
    if (_weight == null || _height == null || _age == null) return;

    final calories = CalorieCalculator.calculateCalorieBudget(
      _weight!,
      _height!,
      _age!,
      _gender,
      _activityLevel,
      _goal,
    );

    setState(() {
      _calculatedCalories = calories;
    });

    // Save to Firebase
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'dailyCalories': calories,
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      _formKey.currentState!.save();
      final user = _auth.currentUser;
      if (user == null) return;

      // Calculate new calorie budget
      await _calculateAndSaveCalories();

      await _firestore.collection('users').doc(user.uid).set({
        'name': _name,
        'gender': _gender,
        'age': _age,
        'activityLevel': _activityLevel,
        'height': _height,
        'weight': _weight,
        'goal': _goal,
        'dailyCalories': _calculatedCalories,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile updated successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      print('Error saving profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User Profile'),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Container(
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
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Color(0xFF2196F3).withOpacity(0.1),
                        child: Icon(
                          Icons.person,
                          size: 50,
                          color: Color(0xFF2196F3),
                        ),
                      ),
                      SizedBox(height: 24),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Personal Information',
                                style: TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: 'Name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) =>
                                    value?.isEmpty ?? true ? 'Please enter your name' : null,
                                onSaved: (value) => _name = value,
                              ),
                              SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _gender,
                                decoration: InputDecoration(
                                  labelText: 'Gender',
                                  prefixIcon: Icon(Icons.people_outline),
                                ),
                                items: ['Male', 'Female', 'Other']
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                    .toList(),
                                onChanged: (value) => setState(() => _gender = value!),
                              ),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _ageController,
                                decoration: InputDecoration(
                                  labelText: 'Age',
                                  prefixIcon: Icon(Icons.calendar_today),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty)
                                    return 'Enter your age';
                                  final age = int.tryParse(value);
                                  if (age == null || age < 1 || age > 120)
                                    return 'Enter a valid age';
                                  return null;
                                },
                                onSaved: (value) => _age = int.tryParse(value!),
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
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Physical Information',
                                style: TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _heightController,
                                decoration: InputDecoration(
                                  labelText: 'Height (cm)',
                                  prefixIcon: Icon(Icons.height),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty)
                                    return 'Enter your height';
                                  final height = double.tryParse(value);
                                  if (height == null || height < 50 || height > 300)
                                    return 'Enter a valid height';
                                  return null;
                                },
                                onSaved: (value) => _height = double.tryParse(value!),
                              ),
                              SizedBox(height: 16),
                              TextFormField(
                                controller: _weightController,
                                decoration: InputDecoration(
                                  labelText: 'Weight (kg)',
                                  prefixIcon: Icon(Icons.monitor_weight_outlined),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty)
                                    return 'Enter your weight';
                                  final weight = double.tryParse(value);
                                  if (weight == null || weight < 20 || weight > 500)
                                    return 'Enter a valid weight';
                                  return null;
                                },
                                onSaved: (value) => _weight = double.tryParse(value!),
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
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weight Goal',
                                style: TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _goal,
                                decoration: InputDecoration(
                                  labelText: 'Goal',
                                  prefixIcon: Icon(Icons.track_changes),
                                ),
                                items: [
                                  'Weight Loss',
                                  'Maintain Weight',
                                  'Weight Gain'
                                ].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _goal = value);
                                  }
                                },
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
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Activity Level',
                                style: TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 16),
                              Column(
                                children: [
                                  Slider(
                                    value: _activityLevel.toDouble(),
                                    min: 1,
                                    max: 4,
                                    divisions: 3,
                                    label: _getActivityLabel(_activityLevel),
                                    activeColor: Color(0xFF2196F3),
                                    inactiveColor: Color(0xFF2196F3).withOpacity(0.2),
                                    onChanged: (value) =>
                                        setState(() => _activityLevel = value.round()),
                                  ),
                                  Text(
                                    _getActivityLabel(_activityLevel),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF1565C0),
                                      fontWeight: FontWeight.w500,
                                    ),
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
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Daily Calorie Budget',
                                style: TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${_calculatedCalories!.round()}',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'calories/day',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Based on your ${_goal.toLowerCase()} goal',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text('Save Profile'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
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

  String _getActivityLabel(int level) {
    switch (level) {
      case 1:
        return 'Sedentary (little or no exercise)';
      case 2:
        return 'Lightly active (light exercise/sports 1-3 days/week)';
      case 3:
        return 'Moderately active (moderate exercise/sports 3-5 days/week)';
      case 4:
        return 'Very active (hard exercise/sports 6-7 days/week)';
      default:
        return 'Unknown';
    }
  }
} 