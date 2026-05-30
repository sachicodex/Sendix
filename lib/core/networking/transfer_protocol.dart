import 'dart:async';
import 'dart:typed_data';

class FrameType {
  static const int hello = 1;
  static const int accept = 2;
  static const int reject = 3;
  static const int fileStart = 4;
  static const int chunk = 5;
  static const int fileEnd = 6;
  static const int transferEnd = 7;
  static const int error = 8;
  static const int progress = 9;
  static const int pause = 10;
  static const int resume = 11;
  static const int cancel = 12;
}

class Frame {
  Frame(this.type, this.payload);

  final int type;
  final Uint8List payload;
}

class FrameCodec {
  static const int headerSize = 5;

  static Uint8List encode(Frame frame) {
    final header = ByteData(headerSize);
    header.setUint8(0, frame.type);
    header.setUint32(1, frame.payload.length, Endian.big);
    final bytes = Uint8List(headerSize + frame.payload.length);
    bytes.setRange(0, headerSize, header.buffer.asUint8List());
    bytes.setRange(headerSize, bytes.length, frame.payload);
    return bytes;
  }
}

class FrameDecoder extends StreamTransformerBase<List<int>, Frame> {
  @override
  Stream<Frame> bind(Stream<List<int>> stream) {
    final controller = StreamController<Frame>();
    var buffer = BytesBuilder();

    void emitFrames() {
      final data = buffer.toBytes();
      var offset = 0;
      while (data.length - offset >= FrameCodec.headerSize) {
        final header = ByteData.sublistView(
          data,
          offset,
          offset + FrameCodec.headerSize,
        );
        final type = header.getUint8(0);
        final length = header.getUint32(1, Endian.big);
        if (data.length - offset - FrameCodec.headerSize < length) {
          break;
        }

        final start = offset + FrameCodec.headerSize;
        final end = start + length;
        final payload = Uint8List.sublistView(data, start, end);
        controller.add(Frame(type, payload));
        offset = end;
      }

      if (offset > 0) {
        buffer = BytesBuilder()..add(data.sublist(offset));
      }
    }

    stream.listen(
      (chunk) {
        buffer.add(chunk);
        emitFrames();
      },
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: true,
    );

    return controller.stream;
  }
}
