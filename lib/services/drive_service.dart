import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriveService {
  static final DriveService _instance = DriveService._internal();
  DriveService._internal();
  factory DriveService() => _instance;

  static const String _gasUrl = 'https://script.google.com/macros/s/AKfycbwg7WGNG222Zs-pQkYskdbYMoFl3a3u5SPci0lIgwuvgmlUtX3t7So73FHLDHJLC3DE/exec';
  static const String _apiKey = 'criblog@123@criblog';
  static const String _serverClientId = '968467901875-5mtlucgu2er4ol2dt9l0g93o4j7oc7nj.apps.googleusercontent.com';
  static const List<String> scopes = ['email'];

  GoogleSignIn? _googleSignIn;
  bool _isInitialized = false;
  bool _isSigningIn = false;

  Future<void> _initializeGoogleSignIn() async {
    if (_isInitialized) return;
    _googleSignIn = GoogleSignIn.instance;
    await _googleSignIn!.initialize(
      clientId: null,
      serverClientId: _serverClientId,
    );
    _googleSignIn!.authenticationEvents.listen(_handleAuthenticationEvent, onError: _handleAuthenticationError);
    _isInitialized = true;
  }

  Future<void> _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
    print("Handle auth event $event");
    final prefs = await SharedPreferences.getInstance();
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        if (event.user != null) {
          await prefs.setString('google_user_email', event.user!.email);
          await prefs.setString('google_user_name', event.user!.displayName ?? event.user!.email);
          debugPrint('DriveService: Authentication event - stored user email=${event.user!.email}, name=${event.user!.displayName}');
        }
        break;
      case GoogleSignInAuthenticationEventSignOut():
        await prefs.remove('google_user_email');
        await prefs.remove('google_user_name');
        debugPrint('DriveService: Authentication event - signed out, cleared user data');
        break;
    }
  }

  Future<void> _handleAuthenticationError(Object e) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_user_email');
    await prefs.remove('google_user_name');
    debugPrint('DriveService: Authentication error: $e');
  }

  Future<void> signInAndStoreUser() async {
    if (_isSigningIn) return;
    _isSigningIn = true;
    await _initializeGoogleSignIn();

    try {
      await _googleSignIn!.signOut();
      final user = await _googleSignIn!.authenticate();
      if (user == null) {
        debugPrint('DriveService: Authentication cancelled or failed');
        throw Exception('Google Sign-In failed: User cancelled or no user returned');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('google_user_email', user.email);
      await prefs.setString('google_user_name', user.displayName ?? user.email);
      debugPrint('DriveService: Stored user email=${user.email}, name=${user.displayName}');

      print("Disconnecting");
      await _googleSignIn!.disconnect();
      print("Disconnected now");
    } on GoogleSignInException catch (e) {
      debugPrint('DriveService: Google Sign-In error: ${e.code} - $e');
      rethrow;
    } catch (e) {
      debugPrint('DriveService: Sign-in failed: $e');
      rethrow;
    } finally {
      _isSigningIn = false;
    }
  }

  Future<void> signOut() async {
    print("Called signout");
    await _initializeGoogleSignIn();
    await _googleSignIn!.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_user_email');
    await prefs.remove('google_user_name');
    debugPrint('DriveService: Signed out, cleared user data');
  }

  Future<String?> get currentUserEmail async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google_user_email');
  }

  Future<String?> get currentUserName async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google_user_name');
  }

  Future<Map<String, dynamic>> checkSync(String lastSyncId) async {
    final client = HttpClient();
    try {
      final prefs = await SharedPreferences.getInstance();
      final destinationUrl = prefs.getString('destination_url') ?? '';
      final payload = {
        'action': 'check_sync',
        'lastSyncId': lastSyncId,
        'destination_url': destinationUrl,
      };

      final uri = Uri.parse('$_gasUrl?key=$_apiKey');
      final request = await client.postUrl(uri);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      print("Sending checkSync request: $payload to $uri");
      final response = await request.close();
      print("Received response: ${response.statusCode}");

      if (response.statusCode == HttpStatus.found || response.statusCode == HttpStatus.temporaryRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        print("Received redirect: $location");
        if (location != null) {
          final redirectedUri = Uri.parse(location);
          final redirectedRequest = await client.getUrl(redirectedUri);
          final redirectedResponse = await redirectedRequest.close();
          final responseBody = await redirectedResponse.transform(utf8.decoder).join();
          final decoded = jsonDecode(responseBody);

          print("Decoded response: $decoded");
          if (decoded['destination_url'] != null) {
            await prefs.setString('destination_url', decoded['destination_url']);
            debugPrint('DriveService: Stored destination_url: ${decoded['destination_url']}');
          }

          if (!['sync_ok', 'updates_needed', 'push_needed'].contains(decoded['status'])) {
            throw Exception('GAS check sync failed after redirect: $responseBody');
          }
          debugPrint('DriveService: Check sync response: $decoded');
          return decoded;
        } else {
          throw Exception('Redirect location not provided');
        }
      }

      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GAS check sync failed: $responseBody', uri: uri);
      }
      final decoded = jsonDecode(responseBody);
      if (!['sync_ok', 'updates_needed', 'push_needed'].contains(decoded['status'])) {
        throw Exception('GAS check sync failed: $responseBody');
      }
      debugPrint('DriveService: Check sync response: $decoded');
      return decoded;
    } catch (e) {
      debugPrint('DriveService: Check sync failed: $e');
      return {
        'status': 'error',
        'message': e.toString(),
        'deltas': [],
        'lastSyncId': lastSyncId,
        'lastSyncTimestamp': DateTime(1970).toIso8601String(),
        'version': '1.0.0'
      };
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> pushDeltas(List<Map<String, dynamic>> deltas, String lastSyncId) async {
    final client = HttpClient();
    try {
      final prefs = await SharedPreferences.getInstance();
      final destinationUrl = prefs.getString('destination_url') ?? '';
      final payload = {
        'action': 'push_deltas',
        'lastSyncId': lastSyncId,
        'deltas': deltas,
        'destination_url': destinationUrl,
      };

      final uri = Uri.parse('$_gasUrl?key=$_apiKey');
      final request = await client.postUrl(uri);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      print("Sending pushDeltas request: $payload to $uri");
      final response = await request.close();
      print("Received response: ${response.statusCode}");

      if (response.statusCode == HttpStatus.found || response.statusCode == HttpStatus.temporaryRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        print("Received redirect: $location");
        if (location != null) {
          final redirectedUri = Uri.parse(location);
          final redirectedRequest = await client.getUrl(redirectedUri);
          final redirectedResponse = await redirectedRequest.close();
          final responseBody = await redirectedResponse.transform(utf8.decoder).join();
          final decoded = jsonDecode(responseBody);

          if (decoded['destination_url'] != null) {
            await prefs.setString('destination_url', decoded['destination_url']);
            debugPrint('DriveService: Stored destination_url: ${decoded['destination_url']}');
          }

          if (decoded['status'] != 'ack') {
            throw Exception('GAS push deltas failed after redirect: $responseBody');
          }
          debugPrint('DriveService: Successfully pushed deltas to GAS');
          return decoded;
        } else {
          throw Exception('Redirect location not provided');
        }
      }

      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GAS push deltas failed: $responseBody', uri: uri);
      }
      final decoded = jsonDecode(responseBody);
      if (decoded['status'] != 'ack') {
        throw Exception('GAS push deltas failed: $responseBody');
      }
      debugPrint('DriveService: Successfully pushed deltas to GAS');
      return decoded;
    } catch (e) {
      debugPrint('DriveService: Push deltas failed: $e');
      throw Exception('Push deltas failed: $e');
    } finally {
      client.close();
    }
  }
}