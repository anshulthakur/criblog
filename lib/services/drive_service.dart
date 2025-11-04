import 'dart:async';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriveService {

  // Singleton class
  static final DriveService _instance = DriveService._internal();
  DriveService._internal();
  factory DriveService() => _instance;

  bool get isSigningIn => _isSigningIn;

  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/drive',
  ];

  static const String _folderId = '1ztuF2eVMtO4acD3Y-omQves64qUEf9Pj';
  // https://drive.google.com/drive/folders/1ztuF2eVMtO4acD3Y-omQves64qUEf9Pj?usp=drive_link
  static const String _deltaFileName = 'criblog_deltas.json';
  static const String _serverClientId = '968467901875-5mtlucgu2er4ol2dt9l0g93o4j7oc7nj.apps.googleusercontent.com';

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  GoogleSignIn? _googleSignIn;
  bool _isInitialized = false;
  Completer<GoogleSignInAccount?>? _signInCompleter;
  bool _isSigningIn = false;

  String get folderId => _folderId;

  Future<void> _initializeGoogleSignIn() async {
    if (_isInitialized) {
      return;
    }
    _googleSignIn = GoogleSignIn.instance;
    await _googleSignIn!.initialize(
      clientId: null,
      serverClientId: _serverClientId,
    );
    _googleSignIn!.authenticationEvents.listen(_handleAuthenticationEvent, onError: _handleAuthenticationError);
    _isInitialized = true;
  }

  Future<GoogleSignInAccount?> _ensureSignedIn() async {
    await _initializeGoogleSignIn();
    if (_currentUser != null) {
      return _currentUser;
    }

    if (_signInCompleter != null) return _signInCompleter!.future;

    _signInCompleter = Completer();
    try {
      final user = await _googleSignIn!.attemptLightweightAuthentication();
      _currentUser = user;
      _signInCompleter!.complete(user);
      return user;
    } catch (e) {
      print("Ensure signin failed: $e");
      _signInCompleter!.complete(null);
      return null;
    } finally {
      _signInCompleter = null;
    }
  }

  Future<void> _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _currentUser = event.user;
        final headers = await _currentUser!.authorizationClient.authorizationHeaders(scopes);
        if (headers == null) throw Exception('Failed to get authorization headers');
        _driveApi = drive.DriveApi(AuthClient(headers));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sync_drive_authorized', true);
        break;
      case GoogleSignInAuthenticationEventSignOut():
        _currentUser = null;
        _driveApi = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sync_drive_authorized', false);
        break;
    }
  }

  Future<void> _handleAuthenticationError(Object e) async {
    _currentUser = null;
    _driveApi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_drive_authorized', false);
    print("Error on auth: $e");
  }

  Future<bool> get isAuthorized async {
    final user = await _ensureSignedIn();
    return user != null;
  }

  Future<String?> get currentUserEmail async {
    final user = await _ensureSignedIn();
    return user?.email;
  }

  Future<void> signIn() async {
    if (_isSigningIn) return;
    _isSigningIn = true;
    await _initializeGoogleSignIn();

    try {
      _currentUser = await _googleSignIn!.attemptLightweightAuthentication();

      if (_currentUser == null) {
        if (_googleSignIn!.supportsAuthenticate()) {
          await Future.delayed(const Duration(milliseconds: 300));
          //await WidgetsBinding.instance.endOfFrame;
          _currentUser = await _googleSignIn!.authenticate();
        } else {
          throw Exception('Google Sign-In is not supported on this platform.');
        }
      }

      if (_currentUser == null) throw Exception('Google Sign-In failed');

      var authorization = await _currentUser!.authorizationClient.authorizationForScopes(scopes);
      if (authorization == null) {
        authorization = await _currentUser!.authorizationClient.authorizeScopes(scopes);
      }

      final headers = await _currentUser!.authorizationClient.authorizationHeaders(scopes);
      if (headers == null || !headers.containsKey('Authorization')) {
        throw Exception('No access token available');
      }

      final authedClient = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            'Bearer',
            headers['Authorization']!.split(' ').last,
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          null,
          scopes,
        ),
      );

      _driveApi = drive.DriveApi(authedClient);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', true);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        print("Sign-in canceled by user or system: $e");
      } else {
        print("Google Sign-In configuration error: $e");
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      rethrow;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      print("Sign-in failed: $e");
      rethrow;
    } finally {
      _isSigningIn = false;
    }
  }



  Future<void> signOut() async {
    await _initializeGoogleSignIn();
    await _googleSignIn!.disconnect();
    _currentUser = null;
    _driveApi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_drive_authorized', false);
  }

  Future<Map<String, dynamic>> pullDeltas() async {
    if (!await isAuthorized) throw Exception('Not authorized');

    final query = 'name = "$_deltaFileName" and "$_folderId" in parents and trashed = false';
    final fileList = await _driveApi!.files.list(q: query);

    if (fileList.files == null || fileList.files!.isEmpty) {
      return {
        'deltas': [],
        'lastSyncTimestamp': DateTime(1970).toIso8601String(),
        'version': '1.0.0',
      };
    }

    final file = fileList.files!.first;
    final media = await _driveApi!.files.get(file.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = await _collectBytes(media.stream);
    final jsonString = utf8.decode(bytes);

    return json.decode(jsonString);
  }

  Future<void> pushDeltas(Map<String, dynamic> deltaData) async {
    if (!await isAuthorized) throw Exception('Not authorized');

    final jsonString = json.encode(deltaData);
    final media = drive.Media(Stream.value(jsonString.codeUnits), jsonString.length);

    final query = 'name = "$_deltaFileName" and "$_folderId" in parents and trashed = false';
    final fileList = await _driveApi!.files.list(q: query);

    drive.File file;
    if (fileList.files == null || fileList.files!.isEmpty) {
      file = drive.File()..name = _deltaFileName..parents = [_folderId];
      await _driveApi!.files.create(file, uploadMedia: media);
    } else {
      final fileId = fileList.files!.first.id!;
      await _driveApi!.files.update(
        drive.File(), // ✅ no metadata fields
        fileId,
        uploadMedia: media,
      );
    }
  }

  Future<void> checkFolderAccess() async {
    if (!await isAuthorized) throw Exception('Not authorized');

    try {
      final folder = await _driveApi!.files.get(_folderId, $fields: 'id, name, mimeType') as drive.File;

      if (folder.mimeType != 'application/vnd.google-apps.folder') {
        throw Exception('Target is not a folder');
      }
      
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      print("Drive folder access error: $e");
      rethrow;
    }
  }


  Future<List<int>> _collectBytes(Stream<List<int>> stream) async {
    final List<int> bytes = [];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}

class AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
