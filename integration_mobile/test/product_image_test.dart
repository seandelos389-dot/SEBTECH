import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/main.dart';

void main() {
  const pngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
  const webpBase64 =
      'UklGRh4CAABXRUJQVlA4WAoAAAAgAAAAAQAAAQAASUNDUMgBAAAAAAHIAAAAAAQwAABtbnRyUkdCIFhZWiAH4AABAAEAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAACRyWFlaAAABFAAAABRnWFlaAAABKAAAABRiWFlaAAABPAAAABR3dHB0AAABUAAAABRyVFJDAAABZAAAAChnVFJDAAABZAAAAChiVFJDAAABZAAAAChjcHJ0AAABjAAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAAgAAAAcAHMAUgBHAEJYWVogAAAAAAAAb6IAADj1AAADkFhZWiAAAAAAAABimQAAt4UAABjaWFlaIAAAAAAAACSgAAAPhAAAts9YWVogAAAAAAAA9tYAAQAAAADTLXBhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACAAAAAcAEcAbwBvAGcAbABlACAASQBuAGMALgAgADIAMAAxADZWUDggMAAAANABAJ0BKgIAAgABQCYloAJ0ugH4AAOwAP7y63/82BXNc+/3/9Lg/S4P0uD/0pAAAA==';

  test('renders image bytes from an uploaded image data URL', () {
    final image =
        productImageWidget('data:image/png;base64,$pngBase64', Icons.memory)
            as Image;

    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, base64Decode(pngBase64));
  });

  test('accepts case-insensitive image data URL headers', () {
    final widget = productImageWidget(
      'DATA:IMAGE/PNG;BASE64,$pngBase64',
      Icons.memory,
    );

    expect(widget, isA<Image>());
  });

  test('decodes WebP images used by the admin uploader', () async {
    final image =
        productImageWidget('data:image/webp;base64,$webpBase64', Icons.memory)
            as Image;

    expect(image.image, isA<MemoryImage>());
    final codec = await ui.instantiateImageCodec(base64Decode(webpBase64));
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 2);
    expect(frame.image.height, 2);
    frame.image.dispose();
    codec.dispose();
  });
}
