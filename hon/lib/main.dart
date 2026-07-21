import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class AppConfig {
  static const String _encodedUrl = "aHR0cHM6Ly9maW4ucnVuZmxhcmUucnVu";

  static String get httpBaseUrl {
    return utf8.decode(base64.decode(_encodedUrl));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedUser = prefs.getString('username');
  runApp(MyApp(savedUsername: savedUser));
}

class MyApp extends StatelessWidget {
  final String? savedUsername;
  const MyApp({super.key, this.savedUsername});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: MainScreen(initialUser: savedUsername),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String? initialUser;
  const MainScreen({super.key, this.initialUser});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String? currentUsername;
  bool isLoginMode = true;
  bool isConnected = false;

  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _msgController = TextEditingController();

  List<dynamic> allUsers = [];
  List<dynamic> filteredUsers = [];
  List<Map<String, dynamic>> messages = [];
  String activeChatUser = "";

  IO.Socket? _socket;
  int _lastMessageTimestamp = 0;
  Timer? _usersPollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialUser != null) {
      print("👤 کاربر در حافظه ذخیره شده پیدا شد: ${widget.initialUser}");
      currentUsername = widget.initialUser;
      _startConnectionManagers();
    } else {
      print("👤 کاربری ذخیره نشده. صفحه ورود نمایش داده می‌شود.");
    }
  }

  @override
  void dispose() {
    _usersPollTimer?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  void _startConnectionManagers() {
    print("🚀 شروع مدیریت اتصالات...");
    _connectSocket();
    _fetchUsersList();
    _usersPollTimer?.cancel();
    _usersPollTimer = Timer.periodic(const Duration(seconds: 10), (t) => _fetchUsersList());
  }

  void _connectSocket() {
    if (currentUsername == null) {
      print("⚠️ عدم اتصال سوکت: currentUsername خالی است!");
      return;
    }

    print("🔗 تلاش برای ساخت سوکت به آدرس: ${AppConfig.httpBaseUrl}");
    _socket?.dispose();

    try {
      _socket = IO.io(
        AppConfig.httpBaseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(5000)
            .build(),
      );

      _socket!.onConnect((_) {
        print("✅ سوکت با موفقیت وصل شد! ID: ${_socket!.id}");
        setState(() => isConnected = true);
        _socket!.emit('register', [currentUsername, _lastMessageTimestamp]);
      });

      _socket!.on('history', (data) {
        print("📜 دریافت تاریخچه پیام‌ها...");
        if (data is List) {
          for (var m in data) {
            _handleIncomingMessage(Map<String, dynamic>.from(m as Map));
          }
        }
      });

      _socket!.on('chat_message', (data) {
        print("💬 پیام جدید دریافت شد.");
        _handleIncomingMessage(Map<String, dynamic>.from(data as Map));
      });

      _socket!.onDisconnect((_) {
        print("🔌 سوکت قطع شد.");
        setState(() => isConnected = false);
      });

      _socket!.onConnectError((err) {
        print("❌ خطای اتصال (ConnectError): $err");
        setState(() => isConnected = false);
      });

      _socket!.onError((err) {
        print("❌ خطای سوکت (Error): $err");
        setState(() => isConnected = false);
      });

      print("📲 درخواست اتصال (connect) فرستاده شد...");
      _socket!.connect();
    } catch (e) {
      print("🚨 خطای بحرانی هنگام ساخت سوکت: $e");
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> msg) {
    final bool alreadyExists = messages.any((m) =>
        m['from'] == msg['from'] &&
        m['to'] == msg['to'] &&
        m['timestamp'] == msg['timestamp']);
    if (alreadyExists) return;

    final ts = msg['timestamp'];
    final int tsInt = ts is int ? ts : (ts as num).toInt();
    if (tsInt > _lastMessageTimestamp) {
      _lastMessageTimestamp = tsInt;
    }

    setState(() {
      messages.add(msg);
    });

    if (msg['from'] != activeChatUser && msg['from'] != currentUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("پیام جدید از طرف ${msg['from']}: ${msg['text']}"),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  void _authAction() async {
    String user = _userController.text.trim();
    String pass = _passController.text.trim();
    if (user.isEmpty || pass.isEmpty) return;

    String endpoint = isLoginMode ? "/api/login" : "/api/signup";
    try {
      print("🌐 ارسال درخواست HTTP به: ${AppConfig.httpBaseUrl}$endpoint");
      
      // 👈🔧 مشکل اصلی اینجا بود: هدر JSON اضافه نشده بود!
      final res = await http.post(
        Uri.parse("${AppConfig.httpBaseUrl}$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"username": user, "password": pass}),
      );

      print("🌐 پاسخ سرور: کد ${res.statusCode} - بدنه: ${res.body}");

      if (res.statusCode == 200 || res.statusCode == 201) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', user);
        setState(() {
          currentUsername = user;
        });
        _startConnectionManagers();
      } else {
        _showError(isLoginMode ? "نام کاربری یا رمز عبور اشتباه است" : "نام کاربری از قبل استفاده شده است");
      }
    } catch (e) {
      print("🚨 خطای شبکه/HTTP: $e");
      _showError("خطا در اتصال به سرور");
    }
  }

  void _fetchUsersList() async {
    if (currentUsername == null) return;
    try {
      final res = await http.get(Uri.parse("${AppConfig.httpBaseUrl}/api/users"));
      if (res.statusCode == 200) {
        setState(() {
          allUsers = json.decode(res.body);
          allUsers.removeWhere((u) => u['username'] == currentUsername);
          filteredUsers = List.from(allUsers);
        });
      }
    } catch (_) {}
  }

  void _searchUser(String query) {
    setState(() {
      filteredUsers = allUsers
          .where((u) => u['username'].toString().toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _sendMessage() {
    String txt = _msgController.text.trim();
    if (txt.isEmpty || activeChatUser.isEmpty) return;

    var msgData = {
      "from": currentUsername,
      "to": activeChatUser,
      "text": txt,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    };

    _socket?.emit('chat_message', [msgData]);

    setState(() {
      messages.add(msgData);
      _msgController.clear();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _usersPollTimer?.cancel();
    _socket?.dispose();
    _socket = null;
    setState(() {
      currentUsername = null;
      isConnected = false;
      messages.clear();
      activeChatUser = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    if (currentUsername == null) {
      return _buildAuthView();
    }
    return activeChatUser.isEmpty ? _buildUserListView() : _buildChatRoomView();
  }

  // UI بخش‌ها دقیقاً مثل قبل هستند
  Widget _buildAuthView() {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isLoginMode ? "ورود به حساب" : "ثبت نام کاربر جدید",
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _userController,
                    decoration: const InputDecoration(labelText: "نام کاربری", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "رمز عبور", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.blueAccent),
                    onPressed: _authAction,
                    child: Text(isLoginMode ? "ورود" : "ساخت حساب"),
                  ),
                  TextButton(
                    onPressed: () => setState(() => isLoginMode = !isLoginMode),
                    child: Text(isLoginMode ? "حساب ندارید؟ ثبت نام کنید" : "قبلاً ثبت نام کردید؟ وارد شوید"),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserListView() {
    return Scaffold(
      appBar: AppBar(
        title: isConnected
            ? const Text("هون")
            : const Text("در حال اتصال...",
                style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _searchUser,
              decoration: const InputDecoration(
                hintText: "جستجوی کاربر با آیدی...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredUsers.length,
              itemBuilder: (context, index) {
                var user = filteredUsers[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: user['is_online'] ? Colors.green : Colors.grey,
                    child: Text(user['username'][0].toString().toUpperCase()),
                  ),
                  title: Text(user['username']),
                  subtitle: Text(user['is_online'] ? "آنلاین" : "آفلاین",
                      style: TextStyle(color: user['is_online'] ? Colors.green : Colors.grey)),
                  onTap: () => setState(() => activeChatUser = user['username']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatRoomView() {
    var chatMessages = messages.where((m) =>
      (m['from'] == currentUsername && m['to'] == activeChatUser) ||
      (m['from'] == activeChatUser && m['to'] == currentUsername)
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("گفتگو با $activeChatUser"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => activeChatUser = ""),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: chatMessages.length,
              itemBuilder: (context, index) {
                var m = chatMessages[index];
                bool isMe = m['from'] == currentUsername;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blueAccent : Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(m['text'] ?? "", style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(hintText: "تایپ پیام...", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: _sendMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
