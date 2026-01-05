import 'package:equatable/equatable.dart';

/// A participant in a Jam session
class JamParticipant extends Equatable {
  final String id;
  final String name;
  final String? photoUrl;
  final bool isHost;
  final bool canControlPlayback; // Permission to skip, seek, etc.
  final DateTime joinedAt;

  const JamParticipant({
    required this.id,
    required this.name,
    this.photoUrl,
    this.isHost = false,
    this.canControlPlayback = false,
    required this.joinedAt,
  });

  /// Check if participant has control permissions (host always can)
  bool get hasControlPermission => isHost || canControlPlayback;

  JamParticipant copyWith({
    String? id,
    String? name,
    String? photoUrl,
    bool? isHost,
    bool? canControlPlayback,
    DateTime? joinedAt,
  }) {
    return JamParticipant(
      id: id ?? this.id,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      isHost: isHost ?? this.isHost,
      canControlPlayback: canControlPlayback ?? this.canControlPlayback,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'photoUrl': photoUrl,
    'isHost': isHost,
    'canControlPlayback': canControlPlayback,
    'joinedAt': joinedAt.toIso8601String(),
  };

  factory JamParticipant.fromJson(Map<String, dynamic> json) {
    return JamParticipant(
      id: json['id'] as String,
      name: json['name'] as String,
      photoUrl: json['photoUrl'] as String?,
      isHost: json['isHost'] as bool? ?? false,
      canControlPlayback: json['canControlPlayback'] as bool? ?? false,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    photoUrl,
    isHost,
    canControlPlayback,
    joinedAt,
  ];
}

/// Current track in the Jam session
class JamTrack extends Equatable {
  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int durationMs;

  const JamTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnailUrl': thumbnailUrl,
    'durationMs': durationMs,
  };

  factory JamTrack.fromJson(Map<String, dynamic> json) {
    return JamTrack(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      durationMs: json['durationMs'] as int,
    );
  }

  @override
  List<Object?> get props => [videoId, title, artist, thumbnailUrl, durationMs];
}

/// A queue item in the Jam session (track + who added it)
class JamQueueItem extends Equatable {
  final JamTrack track;
  final String addedBy; // userId of who added this track
  final DateTime addedAt;

  const JamQueueItem({
    required this.track,
    required this.addedBy,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'addedBy': addedBy,
    'addedAt': addedAt.toIso8601String(),
  };

  factory JamQueueItem.fromJson(Map<String, dynamic> json) {
    return JamQueueItem(
      track: JamTrack.fromJson(json['track'] as Map<String, dynamic>),
      addedBy: json['addedBy'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [track, addedBy, addedAt];
}

/// Playback state synced across participants
class JamPlaybackState extends Equatable {
  final JamTrack? currentTrack;
  final int positionMs;
  final bool isPlaying;
  final DateTime syncedAt;

  const JamPlaybackState({
    this.currentTrack,
    this.positionMs = 0,
    this.isPlaying = false,
    required this.syncedAt,
  });

  /// Calculate current position accounting for time since sync
  int get currentPositionMs {
    if (!isPlaying || currentTrack == null) return positionMs;
    final elapsed = DateTime.now().difference(syncedAt).inMilliseconds;
    return (positionMs + elapsed).clamp(0, currentTrack!.durationMs);
  }

  Map<String, dynamic> toJson() => {
    'currentTrack': currentTrack?.toJson(),
    'positionMs': positionMs,
    'isPlaying': isPlaying,
    'syncedAt': syncedAt.toIso8601String(),
  };

  factory JamPlaybackState.fromJson(Map<String, dynamic> json) {
    return JamPlaybackState(
      currentTrack: json['currentTrack'] != null
          ? JamTrack.fromJson(json['currentTrack'] as Map<String, dynamic>)
          : null,
      positionMs: json['positionMs'] as int? ?? 0,
      isPlaying: json['isPlaying'] as bool? ?? false,
      syncedAt: DateTime.parse(json['syncedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [currentTrack, positionMs, isPlaying, syncedAt];
}

/// A Jam session
class JamSession extends Equatable {
  final String sessionCode;
  final String hostId;
  final String hostName;
  final List<JamParticipant> participants;
  final JamPlaybackState playbackState;
  final List<JamQueueItem> queue;
  final DateTime createdAt;

  const JamSession({
    required this.sessionCode,
    required this.hostId,
    required this.hostName,
    required this.participants,
    required this.playbackState,
    required this.queue,
    required this.createdAt,
  });

  bool get isHost => participants.any((p) => p.id == hostId && p.isHost);
  int get participantCount => participants.length;

  Map<String, dynamic> toJson() => {
    'sessionCode': sessionCode,
    'hostId': hostId,
    'hostName': hostName,
    'participants': participants.map((p) => p.toJson()).toList(),
    'playbackState': playbackState.toJson(),
    'queue': queue.map((t) => t.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory JamSession.fromJson(Map<String, dynamic> json) {
    return JamSession(
      sessionCode: json['sessionCode'] as String,
      hostId: json['hostId'] as String,
      hostName: json['hostName'] as String,
      participants: (json['participants'] as List)
          .map((p) => JamParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      playbackState: JamPlaybackState.fromJson(
        json['playbackState'] as Map<String, dynamic>,
      ),
      queue:
          (json['queue'] as List?)
              ?.map((t) => JamQueueItem.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  JamSession copyWith({
    String? sessionCode,
    String? hostId,
    String? hostName,
    List<JamParticipant>? participants,
    JamPlaybackState? playbackState,
    List<JamQueueItem>? queue,
    DateTime? createdAt,
  }) {
    return JamSession(
      sessionCode: sessionCode ?? this.sessionCode,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      participants: participants ?? this.participants,
      playbackState: playbackState ?? this.playbackState,
      queue: queue ?? this.queue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    sessionCode,
    hostId,
    hostName,
    participants,
    playbackState,
    queue,
    createdAt,
  ];
}

/// Message types for WebSocket communication
enum JamMessageType {
  // Client → Server
  createSession,
  joinSession,
  leaveSession,
  syncPlayback,
  queueAdd,
  queueRemove,
  queueReorder,

  // Server → Client
  sessionCreated,
  sessionJoined,
  sessionLeft,
  sessionEnded,
  playbackUpdated,
  queueUpdated,
  participantJoined,
  participantLeft,
  error,
}

/// WebSocket message wrapper
class JamMessage {
  final JamMessageType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  JamMessage({required this.type, this.data = const {}, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };

  factory JamMessage.fromJson(Map<String, dynamic> json) {
    return JamMessage(
      type: JamMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => JamMessageType.error,
      ),
      data: json['data'] as Map<String, dynamic>? ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}
