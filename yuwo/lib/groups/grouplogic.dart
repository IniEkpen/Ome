import "dart:convert";
import "package:http/http.dart" as http;
import "groupmodel.dart";

// ASSUMPTION: put your real endpoint here. Kept as a top-level constant
// so both the GET (initial load) and POST/DELETE (respond) calls share it.
const String url = "https://your-api-url-here/groups"; // <-- replace with your real url

// Initial fetch of every group the user is part of (pending + accepted + rejected).
// Separate from groupChoice because groupChoice is specifically for responding
// to an invite -- it always needs a real true/false, never "no choice yet".
Future<List<GroupModel>?> loadGroups() async {
  final uri = Uri.parse(url);

  try {
    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as List;
      return decoded
          .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
          .toList();
    }
    return null;
  } catch (e) {
    return null;
  }
}

// check == true  -> accept invite for `groupname`
// check == false -> decline/leave `groupname`
//
// On success, the server is expected to return the FULL updated list of
// groups (pending + accepted + rejected) as JSON, so the app never has to
// guess what changed -- it just replaces its local list with the response.
Future<List<GroupModel>?> groupChoice(bool check, {required String groupname}) async {
  final uri = Uri.parse(url);
  http.Response response;

  try {
    if (check) {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'username': 'george', // ASSUMPTION: swap for real logged-in user
          'groupname': groupname,
          'choice': check,
        }),
      );
    } else {
      response = await http.delete(
        uri,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'username': 'george', // ASSUMPTION: swap for real logged-in user
          'groupname': groupname,
          'choice': check,
        }),
      );
    }

    if (response.statusCode == 200 || response.statusCode == 204) {
      // 204 = No Content -- nothing to decode, treat as success with no list change.
      if (response.statusCode == 204 || response.body.isEmpty) {
        return [];
      }
      final decoded = jsonDecode(response.body) as List;
      return decoded
          .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
          .toList();
    }

    // Non-success status code -- caller treats null as failure.
    return null;
  } catch (e) {
    // Network error, decode error, etc. -- caller treats null as failure.
    return null;
  }
}

// ASSUMPTION: creating a group posts to a different endpoint/shape than
// groupChoice. Stubbed here so Popup can eventually call it -- you said
// you'll fix Popup later, so this is just wired up and ready.
Future<List<GroupModel>?> createGroup(String groupname, List<String> people) async {
  final uri = Uri.parse(url); // TODO: likely a different endpoint, e.g. "$url/create"

  try {
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'username': 'george', // ASSUMPTION: swap for real logged-in user
        'groupname': groupname,
        'people': people,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body) as List;
      return decoded
          .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
          .toList();
    }
    return null;
  } catch (e) {
    return null;
  }
}




