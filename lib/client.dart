library speak_client;

import 'dart:html';
import 'dart:json' as JSON;
import 'dart:async';

class SpeakClient {
  WebSocket _socket;
  List<int> _sockets;
  int _self;
  var _connections = new Map<int,RtcPeerConnection>();
  var _streams = new List<MediaStream>();

  var _messages;
  var _events = new StreamController();

  var _iceServers = {
    'iceServers': [{
      'url': 'stun:stun.l.google.com:19302'
    }]
  };

  var _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true
    }
  };

  SpeakClient(url) {
    _socket = new WebSocket(url);

    _socket.onOpen.listen((e){
      _send('join', {
        'room': ''
      });
    });

    _socket.onClose.listen((e){});

    _messages = _socket.onMessage.map((e) => JSON.parse(e.data));

    onPeers.listen((message) {
      _self = message['you'];
      _sockets = message['connections'];
    });

    onCandidate.listen((message) {
      var candidate = new RtcIceCandidate({
        'sdpMLineIndex': message['label'],
        'candidate': message['candidate']
      });

      _connections[message['id']].addIceCandidate(candidate);
    });

    onNew.listen((message) {
      var id = message['id'];
      var pc = _createPeerConnection(message['id']);

      _sockets.add(id);
      _connections[id] = pc;
      _streams.forEach((s) {
        pc.addStream(s);
      });
    });

    onOffer.listen((message) {
      var pc = _connections[message['id']];
      pc.setRemoteDescription(new RtcSessionDescription(message['sdp']));
      _createAnswer(message['id'], pc);
    });

    onAnswer.listen((message) {
      var pc = _connections[message['id']];
      pc.setRemoteDescription(new RtcSessionDescription(message['sdp']));
    });
  }

  get onOffer => _messages.where((m) => m['type'] == 'offer');

  get onAnswer => _messages.where((m) => m['type'] == 'answer');

  get onCandidate => _messages.where((m) => m['type'] == 'candidate');

  get onNew => _messages.where((m) => m['type'] == 'new');

  get onPeers => _messages.where((m) => m['type'] == 'peers');

  get onAdd => _events.stream.where((m) => m['type'] == 'add');

  get onRemove => _events.stream.where((m) => m['type'] == 'remove');

  createStream({audio: false, video: false}) {
    var completer = new Completer<MediaStream>();

    window.navigator.getUserMedia(audio: audio, video: video).then((stream) {
      var video = new VideoElement()
        ..autoplay = true
        ..src = Url.createObjectUrl(stream);

      _streams.add(stream);

      _sockets.forEach((s) {
        _connections[s] = _createPeerConnection(s);
      });

      _streams.forEach((s) {
        _connections.forEach((k, c) => c.addStream(s));
      });

      _connections.forEach((s, c) => _createOffer(s, c));

      completer.complete(stream);
    });

    return completer.future;
  }

  _createPeerConnection(id) {
    var pc = new RtcPeerConnection(_iceServers);

    pc.onIceCandidate.listen((e){
      if (e.candidate != null) {
        _send('candidate', {
          'label': e.candidate.sdpMLineIndex,
          'id': id,
          'candidate': e.candidate.candidate
        });
      }
    });

    pc.onAddStream.listen((e) {
      _events.add({
        'type': 'add',
        'data': e
      });
    });

    pc.onRemoveStream.listen((e) {
      _events.add({
        'type': 'remove',
        'data': e
      });
    });

    return pc;
  }

  _createOffer(int socket, RtcPeerConnection pc) {
    pc.createOffer(_constraints).then((RtcSessionDescription s) {
      pc.setLocalDescription(s);
      _send('offer', {
          'id': socket,
          'sdp': {
            'sdp': s.sdp,
            'type': s.type
          }
      });
    });
  }

  _createAnswer(int socket, RtcPeerConnection pc) {
    pc.createAnswer(_constraints).then((RtcSessionDescription s) {
      pc.setLocalDescription(s);
      _send('answer', {
          'id': socket,
          'sdp': {
            'sdp': s.sdp,
            'type': s.type
          }
      });
    });
  }

  _send(event, data) {
    data['type'] = event;
    _socket.send(JSON.stringify(data));
  }
}