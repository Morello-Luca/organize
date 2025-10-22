import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class ConfigSelectorDialog extends StatefulWidget {
  const ConfigSelectorDialog({super.key});

  @override
  State<ConfigSelectorDialog> createState() => _ConfigSelectorDialogState();
}

class _ConfigSelectorDialogState extends State<ConfigSelectorDialog> {
  final StorageService _storage = StorageService();
  final TextEditingController _newConfigController = TextEditingController();
  List<String> _configs = [];
  String _currentConfig = 'default';

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await _storage.getAvailableConfigs();
    final current = await _storage.getCurrentConfig();
    
    setState(() {
      _configs = configs;
      _currentConfig = current;
    });
  }

  Future<void> _createNewConfig() async {
    final name = _newConfigController.text.trim();
    if (name.isEmpty || _configs.contains(name)) return;

    await _storage.addConfig(name);
    _newConfigController.clear();
    await _loadConfigs();
  }

  Future<void> _switchConfig(String configName) async {
    await _storage.setCurrentConfig(configName);
    setState(() {
      _currentConfig = configName;
    });
    // Ricarica i dati per la nuova configurazione
    await _storage.loadAlbumsWithFallback();
  }

  Future<void> _deleteConfig(String configName) async {
    if (configName == 'default') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non puoi eliminare la configurazione default')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina configurazione'),
        content: Text('Vuoi eliminare la configurazione "$configName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.removeConfig(configName);
      await _loadConfigs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings_applications),
          SizedBox(width: 12),
          Text('Gestione Configurazioni'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Configurazioni esistenti
            Text(
              'Configurazioni:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            
            ..._configs.map((config) => ListTile(
              leading: Icon(
                config == _currentConfig ? Icons.check_circle : Icons.radio_button_unchecked,
                color: config == _currentConfig ? Colors.green : Colors.grey,
              ),
              title: Text(config),
              subtitle: FutureBuilder<bool>(
                future: _storage.configHasJsonFile(config),
                builder: (context, snapshot) {
                  final hasFile = snapshot.data ?? false;
                  return Text(
                    hasFile ? 'File JSON presente' : 'Nuova configurazione',
                    style: TextStyle(
                      color: hasFile ? Colors.green : Colors.orange,
                    ),
                  );
                },
              ),
              trailing: config != 'default' ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteConfig(config),
              ) : null,
              onTap: () => _switchConfig(config),
            )),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            
            // Nuova configurazione
            Text(
              'Crea nuova configurazione:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newConfigController,
                    decoration: const InputDecoration(
                      hintText: 'Es: Lavoro, Personale, Vacanze...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _createNewConfig,
                  child: const Text('Crea'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}