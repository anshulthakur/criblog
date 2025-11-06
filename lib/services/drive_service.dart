import 'dart:async';
import 'dart:convert';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:shared_preferences/shared_preferences.dart';

class DriveService {
  static final DriveService _instance = DriveService._internal();
  DriveService._internal();
  factory DriveService() => _instance;

  bool get isSigningIn => _isSigningIn;

  static const List<String> scopes = <String>[
    drive.DriveApi.driveScope, // 'https://www.googleapis.com/auth/drive'
  ];

  static const String _folderId = '1ztuF2eVMtO4acD3Y-omQves64qUEf9Pj';
  static const String _deltaFileName = 'criblog_deltas.json';
  static const String _serverClientId = '968467901875-5mtlucgu2er4ol2dt9l0g93o4j7oc7nj.apps.googleusercontent.com';

  GoogleSignInAccount? _currentUser;
  GoogleSignInClientAuthorization? _authorization;
  drive.DriveApi? _driveApi;
  GoogleSignIn? _googleSignIn;
  bool _isInitialized = false;
  Completer<GoogleSignInAccount?>? _signInCompleter;
  bool _isSigningIn = false;

  String get folderId => _folderId;

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

  Future<GoogleSignInAccount?> _ensureSignedIn({bool isBackground = false}) async {
    await _initializeGoogleSignIn();
    final prefs = await SharedPreferences.getInstance();
    final accountId = prefs.getString('google_account_id');

    if (_currentUser != null && _authorization != null) {
      try {
        final authClient = _authorization!.authClient(scopes: scopes);
        _driveApi = drive.DriveApi(authClient);
        return _currentUser;
      } catch (e) {
        print('DriveService: Credential validation failed: $e');
        _currentUser = null;
        _authorization = null;
        _driveApi = null;
      }
    }

    if (isBackground) {
      if (!(await _googleSignIn!.supportsAuthenticate()) || await _googleSignIn!.authorizationRequiresUserInteraction()) {
        print('DriveService: Background authentication requires UI or is unsupported, skipping');
        return null;
      }
      try {
        final user = await _googleSignIn!.attemptLightweightAuthentication(reportAllExceptions: false);
        if (user != null && (accountId == null || user.id == accountId)) {
          final authorization = await user.authorizationClient.authorizationForScopes(scopes);
          if (authorization != null) {
            _currentUser = user;
            _authorization = authorization;
            final authClient = authorization.authClient(scopes: scopes);
            _driveApi = drive.DriveApi(authClient);
            return user;
          }
        }
        print('DriveService: No valid user or authorization in background');
        return null;
      } catch (e) {
        print('DriveService: Background authentication failed: $e');
        return null;
      }
    }

    if (_signInCompleter != null) return _signInCompleter!.future;

    _signInCompleter = Completer();
    try {
      // Try lightweight authentication first
      GoogleSignInAccount? user = await _googleSignIn!.attemptLightweightAuthentication(reportAllExceptions: false);
      if (user != null && (accountId == null || user.id == accountId)) {
        var authorization = await user.authorizationClient.authorizationForScopes(scopes);
        if (authorization == null) {
          print('DriveService: Initial authorizationForScopes failed, attempting authorizeScopes');
          authorization = await user.authorizationClient.authorizeScopes(scopes);
        }
        if (authorization != null) {
          _currentUser = user;
          _authorization = authorization;
          final authClient = authorization.authClient(scopes: scopes);
          _driveApi = drive.DriveApi(authClient);
          await prefs.setBool('sync_drive_authorized', true);
          await prefs.setString('google_account_id', user.id);
          _signInCompleter!.complete(user);
          return user;
        }
      }

      // If lightweight auth fails or user doesn't match, force full authentication
      await _googleSignIn!.signOut(); // Clear cached credentials to force consent screen
      user = await _googleSignIn!.authenticate();
      if (user == null) {
        throw Exception('Google Sign-In failed: User cancelled or no user returned');
      }
      if (accountId != null && user.id != accountId) {
        throw Exception('Signed-in user does not match stored account ID');
      }

      var authorization = await user.authorizationClient.authorizationForScopes(scopes);
      if (authorization == null) {
        print('DriveService: Initial authorizationForScopes failed, attempting authorizeScopes');
        authorization = await user.authorizationClient.authorizeScopes(scopes);
      }
      if (authorization == null) {
        throw Exception('Authorization failed: Unable to obtain credentials for Drive scope');
      }

      _currentUser = user;
      _authorization = authorization;
      final authClient = authorization.authClient(scopes: scopes);
      _driveApi = drive.DriveApi(authClient);
      await prefs.setBool('sync_drive_authorized', true);
      await prefs.setString('google_account_id', user.id);
      _signInCompleter!.complete(user);
      return user;
    } catch (e) {
      print('DriveService: Ensure sign-in failed: $e');
      _signInCompleter!.complete(null);
      return null;
    } finally {
      _signInCompleter = null;
    }
  }

  Future<void> _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final accountId = prefs.getString('google_account_id');

    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        if (event.user != null && (accountId == null || event.user!.id == accountId)) {
          _currentUser = event.user;
          var authorization = await _currentUser!.authorizationClient.authorizationForScopes(scopes);
          if (authorization == null) {
            print('DriveService: Initial authorizationForScopes failed in event, attempting authorizeScopes');
            authorization = await _currentUser!.authorizationClient.authorizeScopes(scopes);
          }
          if (authorization != null) {
            _authorization = authorization;
            final authClient = authorization.authClient(scopes: scopes);
            _driveApi = drive.DriveApi(authClient);
            await prefs.setBool('sync_drive_authorized', true);
            await prefs.setString('google_account_id', _currentUser!.id);
            print('DriveService: Authentication event - signed in');
          } else {
            _currentUser = null;
            _authorization = null;
            _driveApi = null;
            await prefs.setBool('sync_drive_authorized', false);
            await prefs.remove('google_account_id');
            print('DriveService: Authorization failed during sign-in event');
          }
        }
        break;
      case GoogleSignInAuthenticationEventSignOut():
        _currentUser = null;
        _authorization = null;
        _driveApi = null;
        await prefs.setBool('sync_drive_authorized', false);
        await prefs.remove('google_account_id');
        print('DriveService: Authentication event - signed out');
        break;
    }
  }

  Future<void> _handleAuthenticationError(Object e) async {
    _currentUser = null;
    _authorization = null;
    _driveApi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_drive_authorized', false);
    await prefs.remove('google_account_id');
    print('DriveService: Authentication error: $e');
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
      // Clear cached credentials to force OAuth consent screen
      await _googleSignIn!.signOut();
      _currentUser = await _googleSignIn!.authenticate();
      if (_currentUser == null) {
        throw Exception('Google Sign-In failed: User cancelled or no user returned');
      }

      var authorization = await _currentUser!.authorizationClient.authorizationForScopes(scopes);
      if (authorization == null) {
        print('DriveService: Initial authorizationForScopes failed, attempting authorizeScopes');
        authorization = await _currentUser!.authorizationClient.authorizeScopes(scopes);
      }
      if (authorization == null) {
        throw Exception('Authorization failed: Unable to obtain credentials for Drive scope');
      }

      _authorization = authorization;
      final authClient = authorization.authClient(scopes: scopes);
      _driveApi = drive.DriveApi(authClient);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', true);
      await prefs.setString('google_account_id', _currentUser!.id);
      print('DriveService: Signed in successfully');
    } on GoogleSignInException catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      await prefs.remove('google_account_id');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        print('DriveService: Sign-in canceled by user or system: $e');
      } else {
        print('DriveService: Google Sign-In configuration error: $e');
      }
      rethrow;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_drive_authorized', false);
      await prefs.remove('google_account_id');
      print('DriveService: Sign-in failed: $e');
      rethrow;
    } finally {
      _isSigningIn = false;
    }
  }

  Future<void> signOut() async {
    await _initializeGoogleSignIn();
    await _googleSignIn!.signOut();
    _currentUser = null;
    _authorization = null;
    _driveApi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_drive_authorized', false);
    await prefs.remove('google_account_id');
    print('DriveService: Signed out');
  }

  Future<Map<String, dynamic>> pullDeltas({bool isBackground = false}) async {
    if (!await isAuthorized) {
      if (isBackground) {
        return {
          'deltas': [],
          'lastSyncTimestamp': DateTime(1970).toIso8601String(),
          'version': '1.0.0',
        };
      }
      throw Exception('Not authorized');
    }

    final user = await _ensureSignedIn(isBackground: isBackground);
    if (user == null || _authorization == null) {
      print('DriveService: No valid user or authorization for pullDeltas');
      if (isBackground) {
        return {
          'deltas': [],
          'lastSyncTimestamp': DateTime(1970).toIso8601String(),
          'version': '1.0.0',
        };
      }
      throw Exception('No valid user or authorization');
    }

    try {
      final authClient = _authorization!.authClient(scopes: scopes);
      _driveApi ??= drive.DriveApi(authClient);

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
      print('DriveService: Pull deltas failed: $e');
      if (isBackground) {
        return {
          'deltas': [],
          'lastSyncTimestamp': DateTime(1970).toIso8601String(),
          'version': '1.0.0',
        };
      }
      rethrow;
    }
  }

  Future<void> pushDeltas(Map<String, dynamic> deltaData, {bool isBackground = false}) async {
    if (!await isAuthorized) {
      if (isBackground) return;
      throw Exception('Not authorized');
    }

    final user = await _ensureSignedIn(isBackground: isBackground);
    if (user == null || _authorization == null) {
      print('DriveService: No valid user or authorization for pushDeltas');
      if (isBackground) return;
      throw Exception('No valid user or authorization');
    }

    try {
      final authClient = _authorization!.authClient(scopes: scopes);
      _driveApi ??= drive.DriveApi(authClient);

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
          drive.File(),
          fileId,
          uploadMedia: media,
        );
      }
    } catch (e) {
      print('DriveService: Push deltas failed: $e');
      if (isBackground) return;
      rethrow;
    }
  }

  Future<void> checkFolderAccess({bool isBackground = false}) async {
    if (!await isAuthorized) {
      if (isBackground) return;
      throw Exception('Not authorized');
    }

    final user = await _ensureSignedIn(isBackground: isBackground);
    if (user == null || _authorization == null) {
      print('DriveService: No valid user or authorization for checkFolderAccess');
      if (isBackground) return;
      throw Exception('No valid user or authorization');
    }

    try {
      final authClient = _authorization!.authClient(scopes: scopes);
      _driveApi ??= drive.DriveApi(authClient);

      final folder = await _driveApi!.files.get(_folderId, $fields: 'id, name, mimeType') as drive.File;
      if (folder.mimeType != 'application/vnd.google-apps.folder') {
        throw Exception('Target is not a folder');
      }
    } catch (e) {
      print('DriveService: Drive folder access error: $e');
      if (isBackground) return;
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