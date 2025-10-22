// services/background_metadata_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class BackgroundMetadataService {
  static Future<Map<String, String>> extractMetadata(String imagePath) async {
    return await compute(_extractMetadataInBackground, imagePath);
  }

  static Future<Map<String, String>> _extractMetadataInBackground(String imagePath) async {
    final metadataDict = <String, String>{};
    
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return {'Error': 'File not found at path: $imagePath'};
      }

      final bytes = await file.readAsBytes();
      final decodedImage = img.decodePng(bytes);

      if (decodedImage == null) {
        return {'Warning': 'Image is not a valid PNG or cannot be decoded.'};
      }

      final pngDecoder = img.PngDecoder();
      final pngInfo = pngDecoder.decode(bytes);
      
      if (pngInfo == null) {
        return {'Warning': 'Cannot decode PNG with PngDecoder.'};
      }

      // CORREZIONE: Gestione corretta del tipo Map<dynamic, dynamic>?
      final dynamic pngData = pngInfo;
      
      if (pngData.textData == null) {
        return {'Warning': 'PNG does not contain text metadata.'};
      }

      // CORREZIONE: Convertiamo Map<dynamic, dynamic> in Map<String, String>
      final Map<dynamic, dynamic>? rawTextData = pngData.textData;
      if (rawTextData == null || rawTextData.isEmpty) {
        return {'Warning': 'No text metadata found in PNG.'};
      }

      // Convertiamo tutte le chiavi e valori in String
      final Map<String, String> textData = {};
      rawTextData.forEach((key, value) {
        if (key != null && value != null) {
          textData[key.toString()] = value.toString();
        }
      });

      final metadata = textData['parameters'];

      if (metadata == null || metadata.trim().isEmpty) {
        return {'Warning': 'No "parameters" metadata found in PNG.'};
      }
      
      return _parseMetadataText(metadata);
    } catch (e) {
      return {'Error': 'Failed to extract metadata: ${e.toString()}'};
    }
  }

  static Map<String, String> _parseMetadataText(String metadataText) {
    final metadataDict = <String, String>{};
    
    final parts = metadataText.trim().split("Negative prompt:");
    final promptPositive = parts[0].trim();
    final rest = parts.length > 1 ? parts.sublist(1).join("Negative prompt:") : '';

    metadataDict["Prompt Positive"] = promptPositive;
    
    final parts2 = rest.split("Steps:");
    final promptNegative = parts2[0].trim();
    String rest2 = parts2.length > 1 ? parts2.sublist(1).join("Steps:") : '';

    metadataDict["Prompt Negative"] = promptNegative;
    
    rest2 = rest2.trim();
    final stepsMatch = RegExp(r'^(\d+)').firstMatch(rest2);
    
    if (stepsMatch != null) {
      final stepsValue = stepsMatch.group(1)!;
      metadataDict["Steps"] = stepsValue;
      
      final matchLength = stepsMatch.group(0)!.length;
      rest2 = rest2.substring(matchLength).trim();
      
      if (rest2.startsWith(',')) {
        rest2 = rest2.substring(1).trim();
      }
    }
    
    final keyPairs = rest2.split(',');
    for (final item in keyPairs) {
      final trimmedItem = item.trim();
      if (trimmedItem.isEmpty) continue;
      
      final colonIndex = trimmedItem.indexOf(':');
      if (colonIndex != -1) {
        final key = trimmedItem.substring(0, colonIndex).trim();
        final value = trimmedItem.substring(colonIndex + 1).trim();
        
        if (key.isNotEmpty && key != "Model hash") {
          metadataDict[key] = value;
        }
      }
    }
    
    if (metadataDict.isEmpty) {
      return {'Info': 'No ConfyUI metadata found in this image.'};
    }

    return metadataDict;
  }
}