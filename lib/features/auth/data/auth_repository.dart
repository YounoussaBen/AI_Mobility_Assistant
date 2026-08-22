import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(FirebaseAuth.instance);
});

class AppUser {
  const AppUser({required this.id, required this.isGuest, this.email});

  final String id;
  final bool isGuest;
  final String? email;
}

abstract interface class AuthRepository {
  AppUser? get currentUser;

  Stream<AppUser?> authStateChanges();

  Future<AppUser> continueAsGuest();

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> createAccount({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  @override
  AppUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_mapUser);

  @override
  Future<AppUser> continueAsGuest() async {
    final credential = await _auth.signInAnonymously();
    return _mapUser(credential.user)!;
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _mapUser(credential.user)!;
  }

  @override
  Future<AppUser> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _mapUser(credential.user)!;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  AppUser? _mapUser(User? user) {
    if (user == null) return null;
    return AppUser(id: user.uid, isGuest: user.isAnonymous, email: user.email);
  }
}
