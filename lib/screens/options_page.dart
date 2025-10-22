import 'dart:io';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/file_service.dart';
import '../widgets/navigation_rail.dart';
import '../widgets/config_selector_dialog.dart';

class OptionsPage extends StatefulWidget {
  const OptionsPage({super.key});

  @override
  State<OptionsPage> createState() => _OptionsPageState();
}

class _OptionsPageState extends State<OptionsPage> {
  final StorageService _storage = StorageService();
  final FileService _fileService = FileService();
  
  String? _sourceFolderPath;
  String? _jsonFolderPath;
  String _currentConfig = 'default';
  bool _isCheckingSource = false;
  Map<String, dynamic> _sourceFolderInfo = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final source = await _storage.getSourceFolderPath();
    final json = await _storage.getJsonFolderPath();
    final config = await _storage.getCurrentConfig();
    
    setState(() {
      _sourceFolderPath = source;
      _jsonFolderPath = json;
      _currentConfig = config;
    });

    // Carica info cartella sorgente se esiste
    if (source != null) {
      _checkSourceFolder(source);
    }
  }

  Future<void> _checkSourceFolder(String path) async {
    if (_isCheckingSource) return;
    
    setState(() {
      _isCheckingSource = true;
    });

    final info = await _getSourceFolderInfo(path);
    
    if (mounted) {
      setState(() {
        _sourceFolderInfo = info;
        _isCheckingSource = false;
      });
    }
  }

  // Metodo per ottenere informazioni sulla cartella sorgente
  Future<Map<String, dynamic>> _getSourceFolderInfo(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return {'isValid': false, 'message': 'Cartella non esistente'};
      }

      final contents = await dir.list().toList();
      final imageFiles = contents.where((entity) {
        if (entity is File) {
          final ext = entity.path.toLowerCase().split('.').last;
          return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
        }
        return false;
      }).toList();

      final subfolders = contents.where((entity) => entity is Directory).toList();

      return {
        'isValid': true,
        'totalImages': imageFiles.length,
        'subfolders': subfolders.length,
        'message': 'Trovate ${imageFiles.length} immagini e ${subfolders.length} cartelle'
      };
    } catch (e) {
      return {'isValid': false, 'message': 'Errore: $e'};
    }
  }

  Future<void> _selectSourceFolder() async {
    final folder = await _fileService.pickFolder();
    if (folder != null) {
      setState(() {
        _sourceFolderPath = folder;
        _isCheckingSource = true;
        _sourceFolderInfo = {};
      });

      // Verifica la cartella selezionata
      final info = await _getSourceFolderInfo(folder);
      
      if (info['isValid'] == true) {
        await _storage.setSourceFolderPath(folder);
        _showSnackBar('Cartella sorgente configurata: ${info['message']}');
      } else {
        _showSnackBar('Cartella non valida: ${info['message']}');
        setState(() {
          _sourceFolderPath = null;
        });
        return;
      }

      if (mounted) {
        setState(() {
          _sourceFolderInfo = info;
          _isCheckingSource = false;
        });
      }
    }
  }

  Future<void> _selectJsonFolder() async {
    final folder = await _fileService.pickFolder();
    if (folder != null) {
      await _storage.setJsonFolderPath(folder);
      setState(() {
        _jsonFolderPath = folder;
      });
      _showSnackBar('Cartella JSON configurata');
      
      // Al primo setup, carica automaticamente i dati
      final albums = await _storage.loadAlbumsWithFallback();
      if (albums.isNotEmpty) {
        _showSnackBar('Caricati ${albums.length} album dalla configurazione "$_currentConfig"');
      }
    }
  }

  Future<void> _manageConfigs() async {
    await showDialog(
      context: context,
      builder: (context) => const ConfigSelectorDialog(),
    );
    await _loadData(); // Ricarica per aggiornare la configurazione corrente
  }

  Future<void> _testSourceFolder() async {
    if (_sourceFolderPath == null) return;
    
    await _checkSourceFolder(_sourceFolderPath!);
    
    if (_sourceFolderInfo['isValid'] == true) {
      _showSnackBar('Cartella sorgente verificata: ${_sourceFolderInfo['message']}');
    } else {
      _showSnackBar('Problema con la cartella sorgente: ${_sourceFolderInfo['message']}');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Row(
        children: [
          const AppNavigationRail(selectedIndex: 2),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: ListView(
                physics: const BouncingScrollPhysics(), // Scroll più fluido
                children: [
                  // Header
                  _buildHeaderSection(theme),
                  
                  const SizedBox(height: 40),
                  
                  // Configurazione Corrente
                  _buildCurrentConfigSection(),
                  
                  const SizedBox(height: 32),
                  
                  // Cartella Sorgente
                  _buildSourceFolderSection(),
                  
                  const SizedBox(height: 32),
                  
                  // Cartella JSON
                  _buildJsonFolderSection(),

                  const SizedBox(height: 32),

                  // Informazioni
                  _buildInfoSection(),

                  const SizedBox(height: 40), // Spazio extra in fondo
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.settings,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Impostazioni',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Gestisci configurazioni e percorsi',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentConfigSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, color: Colors.blue[700], size: 24),
              const SizedBox(width: 12),
              Text(
                'Configurazione Corrente',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.blue[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Configurazione: $_currentConfig',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Gestisci Configurazioni'),
            onPressed: _manageConfigs,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceFolderSection() {
    final isValid = _sourceFolderInfo['isValid'] == true;
    final isChecking = _isCheckingSource;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.folder_open,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cartella Sorgente Immagini',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Cartella principale contenente le immagini e le sottocartelle',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Percorso cartella
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sourceFolderPath ?? 'Nessuna cartella selezionata',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _sourceFolderPath != null ? Colors.grey[800] : Colors.grey[500],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      if (_sourceFolderPath != null && _sourceFolderInfo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _sourceFolderInfo['message'] ?? '',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isValid ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              Column(
                children: [
                  FilledButton(
                    onPressed: _selectSourceFolder,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                    ),
                    child: const Text('Seleziona'),
                  ),
                  const SizedBox(height: 8),
                  if (_sourceFolderPath != null)
                    OutlinedButton(
                      onPressed: _isCheckingSource ? null : _testSourceFolder,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                        side: BorderSide(color: Colors.orange[300]!),
                      ),
                      child: _isCheckingSource 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verifica'),
                    ),
                ],
              ),
            ],
          ),
          
          // Dettagli cartella
          if (_sourceFolderPath != null && isValid && !isChecking)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  _buildInfoChip(
                    '${_sourceFolderInfo['totalImages']} immagini',
                    Icons.photo,
                    Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    '${_sourceFolderInfo['subfolders']} cartelle',
                    Icons.folder,
                    Colors.blue,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonFolderSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.backup,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cartella Backup JSON',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Cartella per salvare le configurazioni e i backup',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    _jsonFolderPath ?? 'Seleziona una cartella per iniziare',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _jsonFolderPath != null ? Colors.grey[800] : Colors.grey[500],
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              FilledButton(
                onPressed: _selectJsonFolder,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green[600],
                ),
                child: const Text('Seleziona Cartella'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.help_outline, color: Colors.grey[600], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Come funziona',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1. Seleziona la cartella sorgente con le tue immagini\n'
                  '2. Scegli una cartella per i backup JSON\n'
                  '3. Crea diverse configurazioni per organizzare i tuoi album\n'
                  '4. La cartella sorgente viene sincronizzata automaticamente con gli album',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}