import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

// ============================ Logger ============================
class AppLogger {
  static final List<String> _logs = [];
  static bool _enabled = false;

  static void enable() {
    _enabled = true;
    _logs.clear();
    log('📋 Logger enabled');
  }

  static void disable() {
    _enabled = false;
    log('📋 Logger disabled');
  }

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final formatted = '[$timestamp] $message';
    if (_enabled) {
      _logs.add(formatted);
    }
    print(formatted);
  }

  static String getLogs() => _logs.join('\n');

  static void clear() => _logs.clear();
}

// ============================ AppConfig ============================
class AppConfig {
  // آدرس HTTP (برای درخواست‌های REST)
  static const String httpBaseUrl = "https://fin.runflare.run";

  // آدرس Socket.IO
  static const String socketUrl = "https://fin.runflare.run";
}

// ============================ Main ============================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.log('🚀 App started');
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedUser = prefs.getString('username');
  AppLogger.log('👤 Saved username: $savedUser');
  runApp(MyApp(savedUsername: savedUser));
}

class MyApp extends StatelessWidget {
  final String? savedUsername;
  const MyApp({super.key, this.savedUsername});

  @override
  Widget build(BuildContext context) {
    AppLogger.log('🏗️ Building MyApp');
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

// ============================ MainScreen ============================
class MainScreen extends StatefulWidget {
  final String? initialUser;
  const MainScreen({super.key, this.initialUser});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  // -------------------- State Variables --------------------
  String? currentUsername;
  bool isLoginMode = true;
  bool isConnected = false;
  bool _isLoggingEnabled = false;
  Timer? _loggingHoldTimer;
  bool _isLoggingHoldActive = false;

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

  // -------------------- Lifecycle --------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLogger.log('📱 MainScreen initState');
    if (widget.initialUser != null) {
      AppLogger.log('👤 Found saved user: ${widget.initialUser}');
      currentUsername = widget.initialUser;
      _startConnectionManagers();
    } else {
      AppLogger.log('👤 No saved user, showing auth screen');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usersPollTimer?.cancel();
    _socket?.dispose();
    _loggingHoldTimer?.cancel();
    AppLogger.log('🧹 MainScreen disposed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.log('🔄 Lifecycle state: $state');
    super.didChangeAppLifecycleState(state);
  }

  // -------------------- Connection Managers --------------------
  void _startConnectionManagers() async {
    AppLogger.log('🚀 Starting connection managers for user: $currentUsername');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _lastMessageTimestamp = prefs.getInt('lastMessageTimestamp') ?? 0;
    AppLogger.log('📊 Last message timestamp: $_lastMessageTimestamp');

    _connectSocket();
    _fetchUsersList();
    _usersPollTimer?.cancel();
    _usersPollTimer = Timer.periodic(const Duration(seconds: 5), (t) {
      AppLogger.log('⏱️ Polling users list (timer)');
      _fetchUsersList();
    });
  }

  // -------------------- Socket --------------------
  void _connectSocket() {
    if (currentUsername == null) {
      AppLogger.log('⚠️ Cannot connect socket: currentUsername is null');
      return;
    }

    final socketUrl = AppConfig.socketUrl;
    AppLogger.log('🔗 Attempting socket connection to: $socketUrl');
    _socket?.dispose();

    try {
      _socket = IO.io(
        socketUrl,
        IO.OptionBuilder()
            .setTransports(['polling', 'websocket']) // شروع با polling جهت سازگاری کامل
            .disableAutoConnect()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(5000)
            .build(),
      );

      AppLogger.log('📡 Socket instance created, connecting...');

      _socket!.onConnect((_) {
        AppLogger.log('✅ Socket connected! ID: ${_socket!.id}');
        setState(() => isConnected = true);
        
        // 🔹 اصلاح شده: ارسال مستقیم username بدون کروشه
        _socket!.emit('register', currentUsername);
        AppLogger.log('📤 Emitted register event for $currentUsername');
        _fetchUsersList();
      });

      _socket!.on('history', (data) {
        AppLogger.log('📜 Received history: $data');
        try {
          List<dynamic> msgList;
          if (data is List) {
            if (data.isNotEmpty && data[0] is List) {
              msgList = data[0] as List<dynamic>;
              AppLogger.log('📦 History is double-wrapped, extracting inner list');
            } else {
              msgList = data;
            }
          } else {
            AppLogger.log('⚠️ History data is not a List, ignoring');
            return;
          }
          AppLogger.log('📋 Processing ${msgList.length} history messages');
          for (var m in msgList) {
            if (m is Map) {
              _handleIncomingMessage(Map<String, dynamic>.from(m));
            }
          }
        } catch (e, stack) {
          AppLogger.log('❌ Error processing history: $e\n$stack');
        }
      });

      _socket!.on('chat_message', (data) {
        AppLogger.log('💬 Received chat_message raw: $data');
        try {
          Map<String, dynamic> msgMap;
          if (data is Map) {
            msgMap = Map<String, dynamic>.from(data);
          } else if (data is List && data.isNotEmpty && data[0] is Map) {
            msgMap = Map<String, dynamic>.from(data[0] as Map);
            AppLogger.log('📦 Message is wrapped in list, extracting first element');
          } else {
            AppLogger.log('⚠️ Unknown message format: ${data.runtimeType}');
            return;
          }
          _handleIncomingMessage(msgMap);
        } catch (e, stack) {
          AppLogger.log('❌ Error processing chat_message: $e\n$stack');
        }
      });

      _socket!.on('user_status_change', (data) {
        AppLogger.log('🔄 user_status_change received: $data');
        try {
          Map<String, dynamic> statusData;
          if (data is Map) {
            statusData = Map<String, dynamic>.from(data);
          } else if (data is List && data.isNotEmpty && data[0] is Map) {
            statusData = Map<String, dynamic>.from(data[0] as Map);
            AppLogger.log('📦 Status data wrapped in list, extracting first element');
          } else {
            AppLogger.log('⚠️ Unknown status format: ${data.runtimeType}');
            return;
          }
          final username = statusData['username'] as String?;
          final isOnline = statusData['is_online'] as bool?;
          if (username == null || isOnline == null) {
            AppLogger.log('⚠️ Missing username or is_online in status data');
            return;
          }

          AppLogger.log('🔄 User $username is ${isOnline ? "online" : "offline"}');
          setState(() {
            final idx = allUsers.indexWhere((u) => u['username'] == username);
            if (idx >= 0) {
              allUsers[idx]['is_online'] = isOnline;
              filteredUsers = List.from(allUsers.where((u) =>
                  u['username'].toString().toLowerCase().contains(_searchController.text.toLowerCase())
              ));
              AppLogger.log('✅ Updated user $username status in lists');
            } else {
              AppLogger.log('⚠️ User $username not found in allUsers');
            }
          });
        } catch (e, stack) {
          AppLogger.log('❌ Error processing user_status_change: $e\n$stack');
        }
      });

      _socket!.onDisconnect((_) {
        AppLogger.log('🔌 Socket disconnected');
        setState(() => isConnected = false);
      });

      _socket!.onConnectError((err) {
        AppLogger.log('❌ Socket connect error: $err');
        if (err is Map) {
          AppLogger.log('Error details: ${err.toString()}');
        }
        setState(() => isConnected = false);
      });

      _socket!.onError((err) {
        AppLogger.log('❌ Socket error: $err');
        setState(() => isConnected = false);
      });

      AppLogger.log('📲 Calling socket.connect()');
      _socket!.connect();
    } catch (e, stack) {
      AppLogger.log('🚨 Critical error while creating socket: $e\n$stack');
    }
  }

  // -------------------- Incoming Message Handler --------------------
  void _handleIncomingMessage(Map<String, dynamic> msg) {
    AppLogger.log('📩 Handling incoming message: $msg');
    final bool alreadyExists = messages.any((m) =>
        m['from'] == msg['from'] &&
        m['to'] == msg['to'] &&
        m['timestamp'] == msg['timestamp']);
    if (alreadyExists) {
      AppLogger.log('⏭️ Message already exists, skipping');
      return;
    }

    final ts = msg['timestamp'];
    final int tsInt = ts is int ? ts : (ts as num).toInt();
    if (tsInt > _lastMessageTimestamp) {
      _lastMessageTimestamp = tsInt;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('lastMessageTimestamp', tsInt);
        AppLogger.log('💾 Saved lastMessageTimestamp: $tsInt');
      });
    }

    setState(() {
      messages.add(msg);
    });
    AppLogger.log('✅ Message added to local list');

    if (msg['from'] != activeChatUser && msg['from'] != currentUsername) {
      AppLogger.log('🔔 New message from ${msg['from']}, showing snackbar');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("پیام جدید از طرف ${msg['from']}: ${msg['text']}"),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  // -------------------- Authentication --------------------
  void _authAction() async {
    String user = _userController.text.trim();
    String pass = _passController.text.trim();
    AppLogger.log('🔐 Auth action: mode=${isLoginMode ? "login" : "signup"}, user=$user');

    if (user.isEmpty || pass.isEmpty) {
      AppLogger.log('⚠️ Username or password empty');
      return;
    }

    String endpoint = isLoginMode ? "/api/login" : "/api/signup";
    try {
      AppLogger.log('🌐 Sending HTTP request to ${AppConfig.httpBaseUrl}$endpoint');
      final res = await http.post(
        Uri.parse("${AppConfig.httpBaseUrl}$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"username": user, "password": pass}),
      );

      AppLogger.log('🌐 Response status: ${res.statusCode}, body: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        AppLogger.log('✅ Auth successful for $user');
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', user);
        setState(() {
          currentUsername = user;
        });
        _startConnectionManagers();
      } else {
        String errMsg = isLoginMode ? "نام کاربری یا رمز عبور اشتباه است" : "نام کاربری از قبل استفاده شده است";
        AppLogger.log('❌ Auth failed: $errMsg');
        _showError(errMsg);
      }
    } catch (e, stack) {
      AppLogger.log('🚨 Network/HTTP error: $e\n$stack');
      _showError("خطا در اتصال به سرور");
    }
  }

  // -------------------- Fetch Users --------------------
  void _fetchUsersList() async {
    if (currentUsername == null) {
      AppLogger.log('⚠️ Cannot fetch users: currentUsername is null');
      return;
    }
    AppLogger.log('📋 Fetching users list from ${AppConfig.httpBaseUrl}/api/users');
    try {
      final res = await http.get(Uri.parse("${AppConfig.httpBaseUrl}/api/users"));
      if (res.statusCode == 200) {
        AppLogger.log('✅ Users list fetched successfully');
        setState(() {
          allUsers = json.decode(res.body);
          allUsers.removeWhere((u) => u['username'] == currentUsername);
          filteredUsers = List.from(allUsers);
          AppLogger.log('👥 Users count: ${allUsers.length} (excluding self)');
        });
      } else {
        AppLogger.log('⚠️ Failed to fetch users: status ${res.statusCode}');
      }
    } catch (e, stack) {
      AppLogger.log('❌ Error fetching users: $e\n$stack');
    }
  }

  // -------------------- Search --------------------
  void _searchUser(String query) {
    AppLogger.log('🔍 Searching for: "$query"');
    setState(() {
      filteredUsers = allUsers
          .where((u) => u['username'].toString().toLowerCase().contains(query.toLowerCase()))
          .toList();
      AppLogger.log('🔍 Found ${filteredUsers.length} results');
    });
  }

  // -------------------- Send Message --------------------
  void _sendMessage() {
    String txt = _msgController.text.trim();
    AppLogger.log('✉️ Sending message to $activeChatUser: "$txt"');
    if (txt.isEmpty || activeChatUser.isEmpty) {
      AppLogger.log('⚠️ Cannot send: empty text or no active chat user');
      return;
    }

    var msgData = {
      "from": currentUsername,
      "to": activeChatUser,
      "text": txt,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    };

    AppLogger.log('📤 Emitting chat_message: $msgData');
    
    // 🔹 اصلاح شده: ارسال مستقیم Map بدون کروشه
    _socket?.emit('chat_message', msgData);

    setState(() {
      messages.add(msgData);
      _msgController.clear();
    });
    AppLogger.log('✅ Message sent and added locally');
  }

  // -------------------- UI Helpers --------------------
  void _showError(String msg) {
    AppLogger.log('❌ Showing error: $msg');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red)
    );
  }

  // -------------------- Logging Toggle with Long Press --------------------
  void _startLoggingHold() {
    AppLogger.log('🕒 Long press started on logout button');
    _loggingHoldTimer?.cancel();
    _loggingHoldTimer = Timer(const Duration(seconds: 10), () {
      AppLogger.log('⏰ 10 seconds hold reached! Toggling logging mode.');
      setState(() {
        _isLoggingEnabled = !_isLoggingEnabled;
        if (_isLoggingEnabled) {
          AppLogger.enable();
          AppLogger.log('📋 Logging ENABLED (auto-copy on next long press)');
        } else {
          String logs = AppLogger.getLogs();
          Clipboard.setData(ClipboardData(text: logs));
          AppLogger.log('📋 Logs copied to clipboard (${logs.length} chars)');
          AppLogger.disable();
          AppLogger.log('📋 Logging DISABLED');
        }
        _isLoggingHoldActive = false;
      });
    });
    setState(() {
      _isLoggingHoldActive = true;
    });
  }

  void _cancelLoggingHold() {
    if (_loggingHoldTimer != null && _loggingHoldTimer!.isActive) {
      _loggingHoldTimer!.cancel();
      AppLogger.log('🕒 Long press cancelled before 10 seconds');
    }
    setState(() {
      _isLoggingHoldActive = false;
    });
  }

  // -------------------- Logout --------------------
  void _logout() async {
    AppLogger.log('🚪 Logging out user: $currentUsername');
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
    AppLogger.log('✅ Logout complete');
  }

  // -------------------- Build --------------------
  @override
  Widget build(BuildContext context) {
    if (currentUsername == null) {
      AppLogger.log('🖥️ Building auth view');
      return _buildAuthView();
    }
    AppLogger.log('🖥️ Building main view, activeChatUser: "${activeChatUser}"');
    return activeChatUser.isEmpty ? _buildUserListView() : _buildChatRoomView();
  }

  // ============================ UI Sections ============================
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
                  Text(
                    isLoginMode ? "ورود به حساب" : "ثبت نام کاربر جدید",
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueAccent)
                  ),
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
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: Colors.blueAccent
                    ),
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
          GestureDetector(
            onLongPressStart: (_) => _startLoggingHold(),
            onLongPressEnd: (_) => _cancelLoggingHold(),
            onLongPressCancel: _cancelLoggingHold,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _isLoggingHoldActive
                    ? (_isLoggingEnabled ? Colors.red : Colors.orange)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isLoggingHoldActive
                      ? (_isLoggingEnabled ? Colors.red : Colors.orange)
                      : Colors.grey,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.logout,
                    color: _isLoggingHoldActive ? Colors.white : Colors.grey,
                    size: 24,
                  ),
                  if (_isLoggingHoldActive)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        _isLoggingEnabled ? Icons.check_circle : Icons.copy,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
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
                  subtitle: Text(
                    user['is_online'] ? "آنلاین" : "آفلاین",
                    style: TextStyle(color: user['is_online'] ? Colors.green : Colors.grey)
                  ),
                  onTap: () {
                    AppLogger.log('👤 Tapped on user ${user['username']}');
                    setState(() => activeChatUser = user['username']);
                  },
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
          onPressed: () {
            AppLogger.log('⬅️ Leaving chat with $activeChatUser');
            setState(() => activeChatUser = "");
          },
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
                    decoration: const InputDecoration(
                      hintText: "تایپ پیام...",
                      border: OutlineInputBorder()
                    ),
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
