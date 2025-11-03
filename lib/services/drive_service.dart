import 'dart:async';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DriveService {
  static const String _scope = 'https://www.googleapis.com/auth/drive.file';
  static const String _folderId = '1ztuF2eVMtO4acD3Y-omQves64qUEf9Pj'; // Your folder ID
  static const String _deltaFileName = 'criblog_deltas.json';
  static const String _clientId = '87427269367-nkr4k4gtdomr1k3jj9c82kgg53vukvj3.apps.googleusercontent.com'; // Your client ID
  static const String _serverClientId = '87427269367-3tr6mlp9khafuc7qedf8gi20tuut2gda.apps.googleusercontent.com'; // Your server client ID

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  GoogleSignIn? _googleSignIn;

  String get folderId => _folderId; // Getter for folderId

  DriveService() {
    _initializeGoogleSignIn();
  }

  Future<void> _initializeGoogleSignIn() async {
    _googleSignIn = GoogleSignIn.instance;
    await _googleSignIn!.initialize(
      clientId: _clientId,
      serverClientId: _serverClientId,
    );
    _googleSignIn!.authenticationEvents.listen(_handleAuthenticationEvent, onError: _handleAuthenticationError);
    await _googleSignIn!.attemptLightweightAuthentication();
  }

  Future<void> _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _currentUser = event.user;
        if (_currentUser != null) {
          final headers = await _currentUser!.authorizationClient.authorizationHeaders([_scope]);
          if (headers != null) {
            _driveApi = drive.DriveApi(AuthClient(headers));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('sync_drive_authorized', true);
          }
        }
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
  }

  Future<bool> get isAuthorized async {
    if (_googleSignIn == null) await _initializeGoogleSignIn();
    final user = await _googleSignIn!.attemptLightweightAuthentication();
    return user != null;
  }

  Future<String?> get currentUserEmail async {
    if (_googleSignIn == null) await _initializeGoogleSignIn();
    final user = await _googleSignIn!.attemptLightweightAuthentication();
    return user?.email;
  }

  Future<void> signIn() async {
    if (_googleSignIn == null) await _initializeGoogleSignIn();
    
    try {
      _currentUser = await _googleSignIn!.attemptLightweightAuthentication() ?? await _googleSignIn!.authenticate();
      if (_currentUser == null) {
        throw Exception('Google Sign-In failed');
      }

      final headers = await _currentUser!.authorizationClient.authorizationHeaders([_scope]);
      if (headers == null) {
        throw Exception('Failed to get authorization headers');
      }
      _driveApi = drive.DriveApi(AuthClient(headers));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', true);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (_googleSignIn == null) await _initializeGoogleSignIn();
    await _googleSignIn!.disconnect();
    _currentUser = null;
    _driveApi = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_drive_authorized', false);
  }

  Future<Map<String, dynamic>> pullDeltas() async {
    if (!await isAuthorized) {
      throw Exception('Not authorized');
    }

    try {
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
    } catch (e) {
      throw Exception('Failed to pull deltas: $e');
    }
  }

  Future<List<int>> _collectBytes(Stream<List<int>> stream) async {
    final List<int> bytes = [];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> pushDeltas(Map<String, dynamic> deltaData) async {
    if (!await isAuthorized) {
      throw Exception('Not authorized');
    }

    try {
      final jsonString = json.encode(deltaData);
      final media = drive.Media(Stream.value(jsonString.codeUnits), jsonString.length);

      final query = 'name = "$_deltaFileName" and "$_folderId" in parents and trashed = false';
      final fileList = await _driveApi!.files.list(q: query);

      drive.File file;
      if (fileList.files == null || fileList.files!.isEmpty) {
        file = drive.File()
          ..name = _deltaFileName
          ..parents = [_folderId];
      } else {
        file = drive.File()
          ..id = fileList.files!.first.id
          ..name = _deltaFileName
          ..parents = [_folderId];
      }

      if (file.id != null) {
        await _driveApi!.files.update(file, file.id!, uploadMedia: media);
      } else {
        await _driveApi!.files.create(file, uploadMedia: media);
      }
    } catch (e) {
      throw Exception('Failed to push deltas: $e');
    }
  }

  Future<void> checkFolderAccess() async {
    if (!await isAuthorized) {
      throw Exception('Not authorized');
    }

    try {
      final query = '"$_folderId" in parents and trashed = false';
      final fileList = await _driveApi!.files.list(q: query, $fields: 'files(id)');
      if (fileList.files == null || fileList.files!.isEmpty) {
        throw Exception('Cannot access shared folder. Please check permissions.');
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      rethrow;
    }
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