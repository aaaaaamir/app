import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart' as intl;

void main() {
  runApp(const MyApp());
}

const String baseUrl = "https://fin.runflare.run";
const String wsUrl = "wss://fin.runflare.run/ws";

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'چت',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E0E),
        cardColor: const Color(0xFF1C1C1C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4F8CFF),
          surface: Color(0xFF1C1C1C),
        ),
      ),
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (mounted) {
      if (username != null && username.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainChatScreen(currentUsername: username)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ==================== صفحه ورود و ثبت‌نام ====================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLoginMode = true;
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _passConfirmController = TextEditingController();
  String errorMessage = '';
  bool isLoading = false;

  Future<void> _submit() async {
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    setState(() => errorMessage = '');

    if (user.isEmpty || pass.isEmpty) {
      setState(() => errorMessage = 'لطفاً تمامی فیلدها را پر کنید');
      return;
    }

    if (!isLoginMode) {
      final passConfirm = _passConfirmController.text.trim();
      if (pass.length < 5) {
        setState(() => errorMessage = 'رمز عبور باید حداقل ۵ کاراکتر باشد');
        return;
      }
      if (pass != passConfirm) {
        setState(() => errorMessage = 'رمز عبور و تکرار آن یکسان نیستند');
        return;
      }
    }

    setState(() => isLoading = true);
    final endpoint = isLoginMode ? '/api/login' : '/api/signup';

    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', user);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => MainChatScreen(currentUsername: user)),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          errorMessage = data['error'] ?? (isLoginMode ? 'اطلاعات ورود اشتباه است' : 'نام کاربری قبلاً انتخاب شده است');
        });
      }
    } catch (e) {
      setState(() => errorMessage = 'خطا در ارتباط با سرور');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLoginMode ? 'ورود به حساب' : 'ثبت نام کاربر جدید',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4F8CFF)),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(labelText: 'نام کاربری', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'رمز عبور', border: OutlineInputBorder()),
                ),
                if (!isLoginMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passConfirmController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'تکرار رمز عبور', border: OutlineInputBorder()),
                  ),
                ],
                if (errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F8CFF)),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(isLoginMode ? 'ورود' : 'ثبت نام', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      isLoginMode = !isLoginMode;
                      errorMessage = '';
                    });
                  },
                  child: Text(
                    isLoginMode ? 'حساب ندارید؟ ثبت نام کنید' : 'قبلاً ثبت نام کردید؟ وارد شوید',
                    style: const TextStyle(color: Color(0xFF4F8CFF)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== صفحه اصلی (لیست چت‌ها و گروه‌ها) ====================
class MainChatScreen extends StatefulWidget {
  final String currentUsername;
  const MainChatScreen({super.key, required.this.currentUsername});

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  WebSocketChannel? channel;
  Timer? pollTimer;
  List<dynamic> users = [];
  List<dynamic> groups = [];
  String searchQuery = '';
  bool isConnected = false;

  // ذخیره اطلاعات آخرین پیام‌ها و تعداد خوانده‌نشده‌ها
  Map<String, String> lastMessages = {};
  Map<String, int> unreadCounts = {};

  @override
  void initState() {
    super.initState();
    _loadStoredChatData();
    _connectWebSocket();
    _fetchData();
    pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
  }

  // بارگیری داده‌های ذخیره‌شده
  Future<void> _loadStoredChatData() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLastMsgs = prefs.getString('last_messages_${widget.currentUsername}');
    final rawUnread = prefs.getString('unread_counts_${widget.currentUsername}');

    setState(() {
      if (rawLastMsgs != null) {
        lastMessages = Map<String, String>.from(jsonDecode(rawLastMsgs));
      }
      if (rawUnread != null) {
        unreadCounts = Map<String, int>.from(jsonDecode(rawUnread));
      }
    });
  }

  // ذخیره‌سازی داده‌های چت در حافظه گوشی
  Future<void> _saveChatData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_messages_${widget.currentUsername}', jsonEncode(lastMessages));
    await prefs.setString('unread_counts_${widget.currentUsername}', jsonEncode(unreadCounts));
  }

  void _connectWebSocket() {
    try {
      channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      channel!.sink.add(jsonEncode({
        'type': 'register',
        'username': widget.currentUsername,
        'lastMessageTimestamp': 0,
      }));

      setState(() => isConnected = true);

      channel!.stream.listen(
        (event) {
          final data = jsonDecode(event);
          if (data['type'] == 'chat_message') {
            final String text = data['text'] ?? '';
            final String? sender = data['from'];
            final String? groupId = data['groupId']?.toString();

            // تعیین شناسه چت (اگر گروهی باشد شناسه گروه وگرنه نام فرستنده)
            final String chatKey = groupId ?? sender ?? '';

            if (chatKey.isNotEmpty && sender != widget.currentUsername) {
              setState(() {
                lastMessages[chatKey] = text;
                unreadCounts[chatKey] = (unreadCounts[chatKey] ?? 0) + 1;
              });
              _saveChatData();
            }
          }
        },
        onDone: () {
          setState(() => isConnected = false);
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        },
        onError: (_) {
          setState(() => isConnected = false);
        },
      );
    } catch (_) {
      setState(() => isConnected = false);
    }
  }

  Future<void> _fetchData() async {
    try {
      final resUsers = await http.get(Uri.parse('$baseUrl/api/users'));
      if (resUsers.statusCode == 200) {
        final List list = jsonDecode(resUsers.body);
        setState(() {
          users = list.where((u) => u['username'] != widget.currentUsername).toList();
        });
      }

      final resGroups = await http.get(Uri.parse('$baseUrl/api/groups?username=${widget.currentUsername}'));
      if (resGroups.statusCode == 200) {
        setState(() {
          groups = jsonDecode(resGroups.body);
        });
      }
    } catch (e) {
      // دریافت خطا
    }
  }

  // پاک کردن تعداد پیام‌های خوانده‌نشده هنگام ورود به چت
  void _markAsRead(String key) {
    if (unreadCounts.containsKey(key) && unreadCounts[key]! > 0) {
      setState(() {
        unreadCounts[key] = 0;
      });
      _saveChatData();
    }
  }

  // بروزرسانی آخرین پیام ارسالی توسط خود کاربر
  void _updateLastMessageLocally(String key, String text) {
    setState(() {
      lastMessages[key] = text;
    });
    _saveChatData();
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج از حساب'),
        content: const Text('آیا مطمئن هستید که می‌خواهید از حساب کاربری خود خارج شوید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              channel?.sink.close();
              pollTimer?.cancel();
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('username');
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              }
            },
            child: const Text('خروج', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    channel?.sink.close();
    pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = groups.where((g) => (g['name'] ?? '').toLowerCase().contains(searchQuery.toLowerCase())).toList();
    final filteredUsers = users.where((u) => (u['username'] ?? '').toLowerCase().contains(searchQuery.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isConnected ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(isConnected ? 'متصل' : 'در حال اتصال...', style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'گروه جدید',
            onPressed: () => _showCreateGroupModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'خروج',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (val) => setState(() => searchQuery = val),
              decoration: InputDecoration(
                hintText: 'جستجو در گفتگوها و گروه‌ها...',
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                filled: true,
                fillColor: const Color(0xFF161616),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // لیست گروه‌ها
                ...filteredGroups.map((g) {
                  final String gId = g['id'].toString();
                  final int unread = unreadCounts[gId] ?? 0;
                  final String? lastMsg = lastMessages[gId];

                  return ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFF4F8CFF), child: Icon(Icons.group, color: Colors.white)),
                    title: Text(g['name'] ?? ''),
                    subtitle: Text(
                      lastMsg ?? '${g['memberCount']} عضو، ${g['onlineCount']} آنلاین',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: lastMsg != null ? Colors.white70 : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                    trailing: unread > 0
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF4F8CFF),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                    onTap: () async {
                      _markAsRead(gId);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatRoomScreen(
                            currentUsername: widget.currentUsername,
                            groupId: gId,
                            title: g['name'],
                            onNewMessageSent: (txt) => _updateLastMessageLocally(gId, txt),
                          ),
                        ),
                      );
                      _fetchData();
                    },
                  );
                }),

                // لیست کاربران (چت شخصی)
                ...filteredUsers.map((u) {
                  final String username = u['username'];
                  final int unread = unreadCounts[username] ?? 0;
                  final String? lastMsg = lastMessages[username];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF2F5FCC),
                      child: Text(username[0].toUpperCase()),
                    ),
                    title: Text(username),
                    subtitle: Text(
                      lastMsg ?? (u['is_online'] == true ? 'آنلاین' : 'آفلاین'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: lastMsg != null
                            ? Colors.white70
                            : (u['is_online'] == true ? Colors.green : Colors.grey),
                        fontSize: 12,
                      ),
                    ),
                    trailing: unread > 0
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF4F8CFF),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        : null,
                    onTap: () async {
                      _markAsRead(username);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatRoomScreen(
                            currentUsername: widget.currentUsername,
                            peerUsername: username,
                            title: username,
                            onNewMessageSent: (txt) => _updateLastMessageLocally(username, txt),
                          ),
                        ),
                      );
                      _fetchData();
                    },
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupModal(BuildContext context) {
    final nameController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ساخت گروه جدید', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'نام گروه')),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F8CFF)),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  await http.post(
                    Uri.parse('$baseUrl/api/groups/create'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({'username': widget.currentUsername, 'name': name}),
                  );
                  Navigator.pop(ctx);
                  _fetchData();
                }
              },
              child: const Text('ایجاد گروه'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ==================== صفحه چت (شخصی و گروهی) ====================
class ChatRoomScreen extends StatefulWidget {
  final String currentUsername;
  final String? peerUsername;
  final String? groupId;
  final String title;
  final Function(String text)? onNewMessageSent;

  const ChatRoomScreen({
    super.key,
    required.this.currentUsername,
    this.peerUsername,
    this.groupId,
    required.this.title,
    this.onNewMessageSent,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final List<dynamic> _messages = [];
  final TextEditingController _msgController = TextEditingController();
  WebSocketChannel? channel;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _connectWs();
  }

  void _connectWs() {
    channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    channel!.stream.listen((event) {
      final data = jsonDecode(event);
      if (data['type'] == 'chat_message') {
        if (mounted) {
          setState(() {
            _messages.add(data);
          });
          widget.onNewMessageSent?.call(data['text'] ?? '');
        }
      }
    });
  }

  Future<void> _fetchHistory() async {
    String url = '$baseUrl/api/messages?username=${widget.currentUsername}&limit=100';
    if (widget.peerUsername != null) {
      url += '&peer=${widget.peerUsername}';
    } else if (widget.groupId != null) {
      url += '&groupId=${widget.groupId}';
    }

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List fetched = data['messages'] ?? [];
        setState(() {
          _messages.clear();
          _messages.addAll(fetched);
        });

        // تنظیم آخرین پیام در صورت وجود تاریخچه
        if (fetched.isNotEmpty) {
          widget.onNewMessageSent?.call(fetched.last['text'] ?? '');
        }
      }
    } catch (_) {}
  }

  void _sendMessage() {
    final txt = _msgController.text.trim();
    if (txt.isEmpty) return;

    final msgData = {
      'type': 'chat_message',
      'text': txt,
      if (widget.peerUsername != null) 'to': widget.peerUsername,
      if (widget.groupId != null) 'groupId': widget.groupId,
    };

    channel?.sink.add(jsonEncode(msgData));

    setState(() {
      _messages.add({
        'from': widget.currentUsername,
        'text': txt,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });

    widget.onNewMessageSent?.call(txt);
    _msgController.clear();
  }

  @override
  void dispose() {
    channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, idx) {
                final m = _messages[idx];
                final isMe = m['from'] == widget.currentUsername;
                final timeStr = m['timestamp'] != null
                    ? intl.DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(m['timestamp']))
                    : '';

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF2F5FCC) : const Color(0xFF262626),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(isMe ? 12 : 2),
                        bottomRight: Radius.circular(isMe ? 2 : 12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe && widget.groupId != null)
                          Text(
                            m['from'] ?? '',
                            style: const TextStyle(color: Color(0xFF4F8CFF), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        Text(m['text'] ?? '', style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(timeStr, style: const TextStyle(fontSize: 9, color: Colors.white54)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1C1C1C),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'تایپ پیام...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF4F8CFF)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
