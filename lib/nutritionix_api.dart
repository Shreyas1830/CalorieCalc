import 'dart:convert';
import 'package:http/http.dart' as http;

class NutritionixApi {
  static const String _appId = 'YOUR_APP_ID'; // Replace with your App ID
  static const String _appKey = 'YOUR_APP_KEY'; // Replace with your App Key
  static const String _endpoint =
      'https://trackapi.nutritionix.com/v2/natural/nutrients';

  static Future<Map<String, dynamic>?> fetchNutritionData(String query) async {
    final headers = {
      'x-app-id': _appId,
      'x-app-key': _appKey,
      'Content-Type': 'application/json',
    };

    final body = jsonEncode({'query': query});

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception: $e');
      return null;
    }
  }
}
