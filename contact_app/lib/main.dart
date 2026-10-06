import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const EasyContactsApp());
}

class EasyContactsApp extends StatelessWidget {
  const EasyContactsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Maa Contacts',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const ContactSearchScreen(),
    );
  }
}

class ContactSearchScreen extends StatefulWidget {
  const ContactSearchScreen({super.key});

  @override
  State<ContactSearchScreen> createState() => _ContactSearchScreenState();
}

class _ContactSearchScreenState extends State<ContactSearchScreen> {
  List<Contact> _allContacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    final status = await Permission.contacts.request();
    if (status.isGranted) {
      // Null-safe fetch with properties
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      setState(() {
        _allContacts = contacts;
        _filteredContacts = contacts;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  String _normalizeSound(String text) {
    String s = text.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[aeiouy]+'), 'a');
    s = s.replaceAll('ph', 'f');
    s = s.replaceAll('ee', 'a');
    s = s.replaceAll('oo', 'a');
    s = s.replaceAll('sh', 's');
    s = s.replaceAll('v', 'w');
    s = s.replaceAll('w', 'v');
    s = s.replaceAll(RegExp(r'(.)\1+'), r'$1');
    return s;
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  void _filterContacts(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filteredContacts = _allContacts);
      return;
    }
    final cleanQuery = query.toLowerCase().trim();
    final soundQuery = _normalizeSound(cleanQuery);
    List<Map<String, dynamic>> scored = [];

    for (var contact in _allContacts) {
      // Safe null handling for name
      final rawName = contact.displayName;
      final name = rawName.toLowerCase().trim();
      final soundName = _normalizeSound(name);

      if (name.contains(cleanQuery)) {
        scored.add({'contact': contact, 'score': 0});
        continue;
      }
      if (soundName.contains(soundQuery)) {
        scored.add({'contact': contact, 'score': 1});
        continue;
      }

      final words = name.split(' ');
      int minDistance = _levenshtein(cleanQuery, name);
      for (var word in words) {
        int d = _levenshtein(cleanQuery, word);
        if (d < minDistance) minDistance = d;
      }

      int maxAllowedMistakes = cleanQuery.length <= 4 ? 1 : 2;
      if (minDistance <= maxAllowedMistakes) {
        scored.add({'contact': contact, 'score': 2 + minDistance});
      }
    }

    scored.sort((a, b) => (a['score'] as int).compareTo(b['score'] as int));
    setState(() {
      _filteredContacts = scored.map((e) => e['contact'] as Contact).toList();
    });
  }

  Future<void> _makeCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) return;
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maa Ke Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterContacts,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      hintText: 'Yahan naam likhein...',
                      prefixIcon: const Icon(Icons.search, size: 28),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: _filteredContacts.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final contact = _filteredContacts[index];
                      final name = contact.displayName.isNotEmpty ? contact.displayName : 'No Name';
                      final phone = contact.phones.isNotEmpty ? contact.phones.first.number : 'No number';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade100,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 20, color: Colors.teal, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        subtitle: Text(phone),
                        trailing: const Icon(Icons.phone, color: Colors.green, size: 28),
                        onTap: () {
                          if (contact.phones.isNotEmpty) {
                            _makeCall(contact.phones.first.number);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}