import '../pages/home_data.dart';
import 'auth_service.dart';

class HomeService {
  const HomeService(this._auth);

  final AuthService _auth;

  /// Open bills and recent activity for the signed-in user.
  Future<HomeData> load() async {
    final response = (await _auth.client.get(
      '/users/me/home',
    )).orThrow("Couldn't load your home page.");
    return HomeData.fromJson(response.json ?? const {});
  }
}
