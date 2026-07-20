import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// کلاس مدیریت امن سکرت‌ها - آدرس به صورت BASE64 ذخیره شده تا در دیکامپایل متنی لو نرود.
class AppConfig {
  // مقدار زیر در اصل رمزگذاری شده آدرس سرور شماست (مثلاً http://YOUR-PAS-IP:8080)
  // برای تغییر، آدرس سرور خود را Base64 کنید و اینجا قرار دهید.
  static const String _encodedUrl = "aHR0cHM6Ly9maW4ucnVuZmxhcmUucnVu"; 

  static String get httpBaseUrl {
    return utf8.decode(base64.decode(_encodedUrl));
  }

  static String get wsBaseUrl {
    return httpBaseUrl.replaceFirst("http", "ws");
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
  bool isLongPollingMode = false;
  
  // کنترلرهای ورودی
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _msgController = TextEditingController();

  List<dynamic> allUsers = [];
  List<dynamic> filteredUsers = [];
  List<Map<String, dynamic>> messages = [];
  String activeChatUser = "";
  
  WebSocket? _webSocket;
  Timer? _pollingTimer;
  int64 _lastMessageTimestamp = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialUser != null) {
      currentUsername = widget.initialUser;
      _startConnectionManagers();
    }
  }

  @override
  void dispose() {
    _webSocket?.close();
    _pollingTimer?.cancel();
    super.dispose();
  }

  // --- مدیریت شبکه و سوییچ خودکار بین وب‌سوکت و لانگ‌پولینگ ---

  void _startConnectionManagers() {
    _connectWebSocket();
    _fetchUsersList();
    // بروزرسانی لیست کاربران هر ۱۰ ثانیه
    Timer.periodic(const Duration(seconds: 10), (t) => _fetchUsersList());
  }

  void _connectWebSocket() async {
    if (currentUsername == null) return;
    _pollingTimer?.cancel();

    try {
      final wsUrl = "${AppConfig.wsBaseUrl}/api/ws?username=$currentUsername";
      _webSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));
      
      setState(() {
        isLongPollingMode = false;
      });

      _webSocket!.listen(
        (data) {
          var msg = json.decode(data);
          _handleIncomingMessage(msg);
        },
        onError: (err) => _switchToLongPolling(),
        onDone: () => _switchToLongPolling(),
      );
    } catch (e) {
      _switchToLongPolling();
    }
  }

  void _switchToLongPolling() {
    if (isLongPollingMode) return;
    setState(() {
      isLongPollingMode = true;
    });
    _webSocket?.close();

    // اجرای پولینگ متوالی هر ۵ ثانیه یک‌بار بر اساس ساختار درخواستی
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final response = await http.get(Uri.parse(
          "${AppConfig.httpBaseUrl}/api/poll?username=$currentUsername&last_time=$_lastMessageTimestamp"
        )).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          List<dynamic> newMsgs = json.decode(response.body);
          for (var m in newMsgs) {
            _handleIncomingMessage(m);
          }
        }
      } catch (e) {
        // در صورت خطای کامل شبکه، سیستم صبورانه تکرار می‌کند
      }
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> msg) {
    if (msg['timestamp'] > _lastMessageTimestamp) {
      _lastMessageTimestamp = msg['timestamp'];
    }
    
    setState(() {
      messages.add(msg);
    });

    // اعلان درون‌برنامه‌ای سریع در صورت باز نبودن چت با شخص فرستنده
    if (msg['from'] != activeChatUser && msg['from'] != currentUsername) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("پیام جدید از طرف ${msg['from']}: ${msg['text']}"),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  // --- بخش درخواست‌های HTTP احراز هویت ---

  void _authAction() async {
    String user = _userController.text.trim();
    String pass = _passController.text.trim();
    if (user.isEmpty || pass.isEmpty) return;

    String endpoint = isLoginMode ? "/api/login" : "/api/signup";
    try {
      final res = await http.post(
        Uri.parse("${AppConfig.httpBaseUrl}$endpoint"),
        body: json.encode({"username": user, "password": pass}),
      );

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

    if (!isLongPollingMode && _webSocket != null) {
      _webSocket!.add(json.encode(msgData));
    } else {
      // در حالت لانگ‌پولینگ، ارسال از طریق متد معمولی انجام می‌شود اما دریافت با پولینگ است
      http.post(
        Uri.parse("${AppConfig.httpBaseUrl}/api/ws?username=$currentUsername"),
        body: json.encode(msgData),
      );
    }

    setState(() {
      messages.add(msgData);
      _msgController.clear();
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // --- مدیریت رابط کاربری یکپارچه (UI Views) ---

  @override
  Widget build(BuildContext context) {
    if (currentUsername == null) {
      return _buildAuthView();
    }
    return activeChatUser.isEmpty ? _buildUserListView() : _buildChatRoomView();
  }

  // ۱. صفحه ورود و ثبت نام شیک و یکپارچه
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

  // ۲. صفحه لیست کاربران و فیلتر جستجو با ID
  Widget _buildUserListView() {
    return Scaffold(
      appBar: AppBar(
        title: isLongPollingMode 
            ? const Text("حالت اتصال سخت فعال شد (این حالت اینترنت بیشتری مصرف میکند)", 
                style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold))
            : const Text("هون"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.clear();
              setState(() { currentUsername = null; });
            },
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

  // ۳. محیط چت روم اختصاصی داخل صفحه
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
