import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventChatPage extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventChatPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventChatPage> createState() => _EventChatPageState();
}

class _EventChatPageState extends State<EventChatPage>
    with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  late final SupabaseClient _supabase;
  String? _eventCreatorId;
  bool _isLoading = true;
  final Map<String, String> _userNames = {};
  RealtimeChannel? _channel;

  // Typing indicator
  final Map<String, String> _typingUsers = {}; // userId -> userName
  Timer? _typingDebounce;
  bool _isSendingTyping = false;

  // Dots animation
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadEventCreator();
    _loadMyName();
    _loadMessages();
    _setupRealtimeChannel();
  }

  Future<void> _loadMyName() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId != null) await _getUserName(myId);
  }

  Future<void> _loadEventCreator() async {
    try {
      final response = await _supabase
          .from('events')
          .select('user_id')
          .eq('id', widget.eventId)
          .single();
      if (mounted) setState(() => _eventCreatorId = response['user_id']);
    } catch (e) {
      debugPrint('Error cargando creador: $e');
    }
  }

  Future<String> _getUserName(String userId) async {
    if (_userNames.containsKey(userId)) return _userNames[userId]!;
    try {
      final response = await _supabase
          .from('profiles')
          .select('username, full_name')
          .eq('id', userId)
          .maybeSingle();
      String name = 'Usuario';
      if (response != null) {
        if (response['username']?.toString().isNotEmpty == true) {
          name = response['username'];
        } else if (response['full_name']?.toString().isNotEmpty == true) {
          name = response['full_name'];
        }
      }
      _userNames[userId] = name;
      return name;
    } catch (_) {
      return 'Usuario';
    }
  }

  void _setupRealtimeChannel() {
    final myId = _supabase.auth.currentUser?.id;
    _channel = _supabase.channel('event_chat_${widget.eventId}');

    // Mensajes en tiempo real
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'event_messages',
      filter: PostgresChangeFilter(
        column: 'event_id',
        value: widget.eventId,
        type: PostgresChangeFilterType.eq,
      ),
      callback: (payload) async {
        final msg = Map<String, dynamic>.from(payload.newRecord);
        final userId = msg['user_id'] as String?;
        final myId = _supabase.auth.currentUser?.id;

        // Los mensajes propios ya se agregan localmente al enviar
        if (userId == myId) return;

        if (userId != null && !_userNames.containsKey(userId)) {
          await _getUserName(userId);
        }
        if (!mounted) return;
        setState(() {
          _messages.add(msg);
          if (userId != null) _typingUsers.remove(userId);
        });
        _scrollToBottom();
      },
    );

    // Typing broadcast
    _channel!.onBroadcast(
      event: 'typing',
      callback: (payload) async {
        final userId = payload['user_id'] as String?;
        final isTyping = payload['is_typing'] as bool? ?? false;
        if (userId == null || userId == myId) return;
        String? name = _userNames[userId];
        name ??= await _getUserName(userId);
        if (!mounted) return;
        setState(() {
          if (isTyping) {
            _typingUsers[userId] = name!;
          } else {
            _typingUsers.remove(userId);
          }
        });
      },
    );

    _channel!.subscribe((status, [error]) {
      debugPrint('📡 Canal estado: $status');
    });
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _supabase
          .from('event_messages')
          .select()
          .eq('event_id', widget.eventId)
          .order('created_at', ascending: true);

      for (final msg in messages) {
        final uid = msg['user_id'] as String?;
        if (uid != null && !_userNames.containsKey(uid)) {
          await _getUserName(uid);
        }
      }
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(messages);
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      debugPrint('Error cargando mensajes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onTextChanged(String value) {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    final myName = _userNames[myId] ?? 'Yo';

    if (value.isNotEmpty && !_isSendingTyping) {
      _isSendingTyping = true;
      _channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': myId, 'user_name': myName, 'is_typing': true},
      );
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _isSendingTyping = false;
      _channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': myId, 'user_name': myName, 'is_typing': false},
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    final userEmail = _supabase.auth.currentUser?.email;
    if (userId == null || userEmail == null) return;

    // Cancelar typing
    _typingDebounce?.cancel();
    _isSendingTyping = false;
    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': userId, 'is_typing': false},
    );

    _messageController.clear();

    // ── Optimistic update: mostrar el mensaje INMEDIATAMENTE ─────────────────
    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticMsg = {
      'event_id': widget.eventId,
      'user_id': userId,
      'message': text,
      'user_email': userEmail,
      'created_at': now,
    };
    if (mounted) {
      setState(() => _messages.add(optimisticMsg));
      _scrollToBottom();
    }

    try {
      await _supabase.from('event_messages').insert({
        'event_id': widget.eventId,
        'user_id': userId,
        'message': text,
        'user_email': userEmail,
        'created_at': now,
      });
    } catch (e) {
      debugPrint('Error enviando: $e');
      if (mounted) {
        setState(() => _messages.remove(optimisticMsg));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar', style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _getUserInitial(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : '?';

  Color _getUserColor(String userId) {
    const colors = [
      Colors.blueAccent, Colors.purpleAccent, Colors.tealAccent,
      Colors.pinkAccent, Colors.amberAccent, Colors.indigoAccent,
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m';

    final diff = DateTime.now().difference(local);
    String rel;
    if (diff.inSeconds < 30) {
      rel = 'ahora';
    } else if (diff.inMinutes < 1) {
      rel = 'hace ${diff.inSeconds} s';
    } else if (diff.inHours < 1) {
      rel = 'hace ${diff.inMinutes} min';
    } else if (diff.inDays < 1) {
      rel = 'hace ${diff.inHours} h';
    } else if (diff.inDays < 7) {
      rel = 'hace ${diff.inDays} d';
    } else {
      rel = '${local.day}/${local.month}/${local.year}';
    }

    return '$timeStr · $rel';
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _dotsController.dispose();
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chat del evento',
              style: TextStyle(
                fontFamily: 'Poppins', color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              widget.eventTitle,
              style: const TextStyle(
                fontFamily: 'Poppins', color: Colors.greenAccent,
                fontSize: 14, fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.8),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[700]),
                              const SizedBox(height: 16),
                              Text('No hay mensajes aún',
                                  style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[500], fontSize: 16)),
                              const SizedBox(height: 8),
                              Text('¡Sé el primero en escribir!',
                                  style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[600], fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) => _buildMessage(_messages[i]),
                        ),
                ),
                // Indicador de escritura
                if (_typingUsers.isNotEmpty) _buildTypingIndicator(),
                // Input
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final userId = message['user_id'] as String? ?? '';
    final isMe = userId == _supabase.auth.currentUser?.id;
    final isCreator = userId == _eventCreatorId;
    final userName = _userNames[userId] ?? 'Usuario';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _buildAvatar(userId, userName, isCreator, isMe: false),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFFFC4C02).withOpacity(0.18)
                    : Colors.grey[900],
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: Border.all(
                  color: isMe
                      ? const Color(0xFFFC4C02).withOpacity(0.45)
                      : Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userName,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: _getUserColor(userId),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isCreator) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Creador',
                              style: TextStyle(
                                fontFamily: 'Poppins', color: Colors.orange,
                                fontSize: 8, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    message['message'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Poppins', color: Colors.white, fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(DateTime.parse(message['created_at'])),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: isMe ? const Color(0xFFFC4C02).withOpacity(0.6) : Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatar(userId, userName, isCreator, isMe: true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(String userId, String userName, bool isCreator, {required bool isMe}) {
    final color = isMe ? const Color(0xFFFC4C02) : _getUserColor(userId);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: isCreator ? Colors.orange : color.withOpacity(0.5),
          width: isCreator ? 2 : 1.5,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Text(
              _getUserInitial(userName),
              style: TextStyle(
                fontFamily: 'Poppins', color: color,
                fontWeight: FontWeight.w700, fontSize: 13,
              ),
            ),
          ),
          if (isCreator)
            Positioned(
              bottom: -2, right: -2,
              child: Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  color: Colors.orange, shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0F0F0F), width: 1.5),
                ),
                child: const Icon(Icons.star, color: Colors.black, size: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final names = _typingUsers.values.toList();
    final label = names.length == 1
        ? '${names[0]} está escribiendo'
        : '${names.length} personas están escribiendo';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          _TypingDots(controller: _dotsController),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.grey[500],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              onChanged: _onTextChanged,
              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: TextStyle(fontFamily: 'Poppins', color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFC4C02), shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.black, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animación de tres puntos ──────────────────────────────────────────────────

class _TypingDots extends StatelessWidget {
  final AnimationController controller;
  const _TypingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Cada punto tiene un desfase de 0.2 en el ciclo
            final phase = (controller.value - i * 0.2).clamp(0.0, 1.0);
            final bounce = (phase < 0.5)
                ? phase * 2
                : (1.0 - phase) * 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.grey[700], Colors.greenAccent, bounce,
                ),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.translationValues(0, -4 * bounce, 0),
            );
          }),
        );
      },
    );
  }
}
