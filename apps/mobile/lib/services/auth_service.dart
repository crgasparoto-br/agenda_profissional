import 'package:supabase_flutter/supabase_flutter.dart';

enum AccessPath { professional, client }

class AuthService {
  AuthService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  AccessPath resolveAccessPath([User? user]) {
    final current = user ?? currentUser;
    final raw = current?.userMetadata?["access_path"];
    return raw == "client" ? AccessPath.client : AccessPath.professional;
  }

  Future<AuthResponse> signInWithPassword({required String email, required String password}) async {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
    required AccessPath accessPath,
    String? fullName,
  }) async {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        "access_path": accessPath == AccessPath.client ? "client" : "professional",
        "full_name": fullName,
      },
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
