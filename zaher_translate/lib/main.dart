import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MotarjimApp());

class MotarjimApp extends StatelessWidget {
  const MotarjimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Zaher translate',
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      TranslatePage(),
      GrammarPage(),
      AnalyzePage(),
      CameraPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Zaher translate')),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.translate), label: 'ترجمة'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: 'التدقيق'),
          NavigationDestination(icon: Icon(Icons.account_tree), label: 'التحليل'),
          NavigationDestination(icon: Icon(Icons.camera_alt), label: 'الكاميرا'),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
    );
  }
}

void showMsg(BuildContext context, String m) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

bool isArabicText(String t) => RegExp(r'[\u0600-\u06FF]').hasMatch(t);

// ==================== 1) الترجمة (أوفلاين) ====================

class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  final controller = TextEditingController();
  String result = '';
  bool loading = false;
  bool arToEn = true;
  OnDeviceTranslator? translator;

  @override
  void initState() {
    super.initState();
    _prepareModels();
  }

  Future<void> _prepareModels() async {
    final mgr = OnDeviceTranslatorModelManager();
    try {
      for (final lang in [TranslateLanguage.arabic, TranslateLanguage.english]) {
        if (!await mgr.isModelDownloaded(lang)) {
          await mgr.downloadModel(lang);
        }
      }
    } catch (e) {
      if (mounted) showMsg(context, 'أول مرة بس محتاج نت عشان تنزل موديلات الترجمة، بعدها شغال 100% بدون نت');
    }
  }

  Future<void> _translate() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      loading = true;
      result = '';
    });
    try {
      translator?.close();
      translator = OnDeviceTranslator(
        sourceLanguage: arToEn ? TranslateLanguage.arabic : TranslateLanguage.english,
        targetLanguage: arToEn ? TranslateLanguage.english : TranslateLanguage.arabic,
      );
      final out = await translator!.translateText(text);
      setState(() => result = out);
    } catch (e) {
      if (mounted) showMsg(context, 'حصل خطأ: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    translator?.close();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'اكتب كلمة أو جملة هنا...',
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('عربي ← إنجليزي')),
            ButtonSegment(value: false, label: Text('إنجليزي ← عربي')),
          ],
          selected: {arToEn},
          onSelectionChanged: (s) => setState(() => arToEn = s.first),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: loading ? null : _translate,
          icon: const Icon(Icons.translate),
          label: Text(loading ? 'بترجم...' : 'ترجم'),
        ),
        const SizedBox(height: 16),
        if (result.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(result, style: const TextStyle(fontSize: 18)),
            ),
          ),
      ],
    );
  }
}

// ==================== 2) التدقيق النحوي ====================

class GError {
  final String message;
  final String wrong;
  final String fix;
  GError({required this.message, required this.wrong, required this.fix});
}

// تدقيق أوفلاين بقواعد بسيطة (من غير نت خالص)
List<GError> checkOffline(String text) {
  final errs = <GError>[];
  final t = text.trim();
  if (t.isEmpty) return errs;

  if (isArabicText(t)) {
    if (t.contains('  ')) {
      errs.add(GError(message: 'في مسافة مزدوجة', wrong: '  ', fix: ' '));
    }
    for (final m in RegExp(r'\bاذا\b').allMatches(t)) {
      errs.add(GError(message: 'لازم همزة على الألف', wrong: 'اذا', fix: 'إذا'));
    }
    for (final m in RegExp(r'\bالى\b').allMatches(t)) {
      errs.add(GError(message: 'الصح: إلى بهمزة', wrong: 'الى', fix: 'إلى'));
    }
    for (final m in RegExp(r'\bايه\b').allMatches(t)) {
      errs.add(GError(message: 'لو قاصد "أي" بحرف معنى لازم همزة', wrong: 'ايه', fix: 'أيه'));
    }
    if (!RegExp(r'[.!؟?]$').hasMatch(t)) {
      errs.add(GError(
          message: 'الجملة محتاجة علامة ترقيم في الآخر',
          wrong: t.split(' ').last,
          fix: '${t.split(' ').last}.'));
    }
  } else {
    final words = t.split(RegExp(r'\s+'));
    for (var i = 1; i < words.length; i++) {
      final a = words[i - 1].toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      final b = words[i].toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (a.isNotEmpty && a == b) {
        errs.add(GError(message: 'كلمة مكررة', wrong: words[i], fix: ''));
      }
    }
    if (RegExp(r'\bi\b').hasMatch(t)) {
      errs.add(GError(message: 'ضمير I لازم يكون Capital دايمًا', wrong: 'i', fix: 'I'));
    }
    if (RegExp(r'^[a-z]').hasMatch(t)) {
      errs.add(GError(
          message: 'أول حرف في الجملة لازم يكون Capital',
          wrong: t[0],
          fix: t[0].toUpperCase()));
    }
    if (RegExp(r'\.[A-Za-z]').hasMatch(t)) {
      errs.add(GError(message: 'محتاج مسافة بعد النقطة', wrong: '.', fix: '. '));
    }
    for (final m in RegExp(r'\ba ([aeiou])', caseSensitive: false).allMatches(t)) {
      errs.add(GError(
          message: 'قبل الحروف المتحركة بنستخدم an مش a',
          wrong: m.group(0)!,
          fix: 'an ${m.group(1)}'));
    }
    if (!RegExp(r'[.!?]$').hasMatch(t)) {
      errs.add(GError(
          message: 'الجملة محتاجة علامة ترقيم في الآخر',
          wrong: t.split(' ').last,
          fix: '${t.split(' ').last}.'));
    }
  }
  return errs;
}

class GrammarPage extends StatefulWidget {
  const GrammarPage({super.key});

  @override
  State<GrammarPage> createState() => _GrammarPageState();
}

class _GrammarPageState extends State<GrammarPage> {
  final controller = TextEditingController();
  List<GError> errors = [];
  bool loading = false;
  bool checked = false;
  bool online = false; // وضع أوفلاين هو الأساسي

  Future<void> _check() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      loading = true;
      errors = [];
      checked = false;
    });
    if (!online) {
      setState(() {
        errors = checkOffline(text);
        checked = true;
        loading = false;
      });
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('https://api.languagetool.org/v2/check'),
        body: {'text': text, 'language': 'auto'},
      );
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final list = <GError>[];
      for (final m in (data['matches'] as List? ?? [])) {
        final ctx = (m['context']?['text'] ?? '') as String;
        final off = (m['offset'] ?? 0) as int;
        final len = (m['length'] ?? 0) as int;
        final wrong = (off + len <= ctx.length) ? ctx.substring(off, off + len) : ctx;
        String fix = '';
        final reps = m['replacements'] as List?;
        if (reps != null && reps.isNotEmpty) fix = reps.first['value'] ?? '';
        list.add(GError(message: m['message'] ?? '', wrong: wrong, fix: fix));
      }
      setState(() {
        errors = list;
        checked = true;
      });
    } catch (e) {
      if (mounted) showMsg(context, 'التدقيق الأونلاين محتاج نت — اقفل الوضع الأونلاين');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('تدقيق أونلاين (أقوى لكن محتاج نت)'),
          subtitle: const Text('اقفله = تدقيق أوفلاين بالقواعد، من غير نت خالص'),
          value: online,
          onChanged: (v) => setState(() => online = v),
        ),
        TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'اكتب جملة عربي أو إنجليزي وأنا أدققها...',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: loading ? null : _check,
          icon: const Icon(Icons.fact_check),
          label: Text(loading ? 'بيدقق...' : 'دقق الجملة'),
        ),
        const SizedBox(height: 16),
        if (checked && errors.isEmpty)
          const Card(
            color: Colors.green,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('مفيش أخطاء — الجملة سليمة 🎉',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ...errors.map((e) => Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: e.wrong,
                      style: const TextStyle(
                          color: Colors.red,
                          decoration: TextDecoration.lineThrough)),
                  const TextSpan(text: '  ←  '),
                  TextSpan(
                      text: e.fix.isEmpty ? '(امسح التكرار)' : e.fix,
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                ])),
                subtitle: Text(e.message),
              ),
            )),
      ],
    );
  }
}

// ==================== 3) التحليل النحوي (أوفلاين) ====================

class WordTag {
  final String word;
  final String tag;
  final Color color;
  WordTag(this.word, this.tag, this.color);
}

const arConj = {'و', 'ف', 'ثم', 'أو', 'او', 'بل'};
const arPrep = {'في', 'علي', 'على', 'الي', 'إلى', 'من', 'عن', 'مع', 'ب', 'ل', 'ك', 'لدى', 'لدي'};
const arNeg = {'ما', 'لم', 'لا', 'لن', 'ليس', 'ليست'};
const arPron = {'أنا', 'انا', 'نحن', 'أنت', 'انت', 'أنتِ', 'انتي', 'هو', 'هي', 'هم', 'هن'};
const arVerbs = [
  'كتب', 'يكتب', 'اكتب', 'قرأ', 'يقرأ', 'اقرأ', 'ذهب', 'يذهب', 'اذهب',
  'أكل', 'اكل', 'يأكل', 'آكل', 'شرب', 'يشرب', 'اشرب', 'درس', 'يدرس', 'ادرس',
  'عمل', 'يعمل', 'اعمل', 'شاهد', 'يشاهد', 'فتح', 'يفتح', 'افتح', 'لعب', 'يلعب',
  'العب', 'رسم', 'يرسم', 'ارسم', 'سمع', 'يسمع', 'اسمع', 'قال', 'يقول', 'قول',
  'نام', 'ينام', 'نم', 'شاف', 'راح', 'يروح', 'روح', 'خد', 'ياخد', 'اخد',
];

const enPrep = {'in', 'on', 'at', 'to', 'from', 'with', 'of', 'for', 'by', 'about'};
const enPron = {'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them'};
const enArt = {'a', 'an', 'the'};
const enAux = {'is', 'am', 'are', 'was', 'were', 'do', 'does', 'did', 'have', 'has', 'had', 'will', 'would', 'can', 'could'};
const enVerbs = {
  'go', 'goes', 'went', 'eat', 'eats', 'ate', 'read', 'reads', 'write', 'writes', 'wrote',
  'play', 'plays', 'played', 'study', 'studies', 'studied', 'work', 'works', 'worked',
  'like', 'likes', 'liked', 'see', 'sees', 'saw', 'watch', 'watches', 'watched',
  'drink', 'drinks', 'drank', 'run', 'runs', 'ran', 'walk', 'walks', 'walked', 'love', 'loves', 'loved'
};

bool _isArVerb(String w) {
  var v = w;
  if (v.length > 1 && (v.startsWith('و') || v.startsWith('ف'))) {
    v = v.substring(1);
  }
  return arVerbs.contains(v) || arVerbs.contains(w);
}

List<WordTag> analyze(String text) {
  final arabic = isArabicText(text);
  final raw = text.trim().split(RegExp(r'\s+'));
  final tags = <WordTag>[];
  bool verbFound = false, subjFound = false, nounFound = false, kanaFound = false;

  for (var i = 0; i < raw.length; i++) {
    final w = raw[i].replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z]'), '');
    if (w.isEmpty) continue;

    if (arabic) {
      if (arConj.contains(w)) {
        tags.add(WordTag(w, 'حرف عطف', Colors.blueGrey));
      } else if (arPrep.contains(w)) {
        tags.add(WordTag(w, 'حرف جر', Colors.teal));
      } else if (arNeg.contains(w)) {
        tags.add(WordTag(w, 'حرف نفي', Colors.orange));
      } else if (w == 'كان' || w == 'أصبح' || w == 'اصبح' || w == 'أمسى' || w == 'امسى') {
        tags.add(WordTag(w, 'كان وأخواتها (ناسخ)', Colors.purple));
        kanaFound = true;
      } else if (_isArVerb(w)) {
        tags.add(WordTag(w, w.startsWith('ي') ? 'فعل مضارع' : 'فعل ماضٍ', Colors.blue));
        verbFound = true;
      } else if (arPron.contains(w)) {
        tags.add(WordTag(w, 'ضمير', Colors.brown));
      } else if (kanaFound) {
        tags.add(WordTag(w, 'خبر كان', Colors.purple.shade200));
        kanaFound = false;
      } else if (verbFound && !subjFound) {
        tags.add(WordTag(w, 'فاعل', Colors.green));
        subjFound = true;
      } else if (verbFound && subjFound && w.startsWith('ال')) {
        tags.add(WordTag(w, 'مفعول به (تقديري)', Colors.red));
      } else if (!verbFound && !nounFound) {
        tags.add(WordTag(w, 'مبتدأ', Colors.green));
        nounFound = true;
      } else if (!verbFound && nounFound) {
        tags.add(WordTag(w, 'خبر', Colors.green.shade300));
      } else {
        tags.add(WordTag(w, 'اسم/كلمة', Colors.grey));
      }
    } else {
      final lw = w.toLowerCase();
      if (enArt.contains(lw)) {
        tags.add(WordTag(w, 'أداة تعريف/تنكير', Colors.blueGrey));
      } else if (enPron.contains(lw)) {
        tags.add(WordTag(w, 'ضمير', Colors.brown));
      } else if (enPrep.contains(lw)) {
        tags.add(WordTag(w, 'حرف جر', Colors.teal));
      } else if (enAux.contains(lw)) {
        tags.add(WordTag(w, 'فعل مساعد', Colors.purple));
        verbFound = true;
      } else if (enVerbs.contains(lw)) {
        tags.add(WordTag(w, 'فعل رئيسي', Colors.blue));
        verbFound = true;
      } else if (verbFound && !subjFound) {
        tags.add(WordTag(w, 'فاعل/اسم', Colors.green));
        subjFound = true;
      } else if (verbFound && subjFound) {
        tags.add(WordTag(w, 'مفعول به (تقديري)', Colors.red));
      } else {
        tags.add(WordTag(w, 'اسم', Colors.grey));
      }
    }
  }
  return tags;
}

class AnalyzePage extends StatefulWidget {
  const AnalyzePage({super.key});

  @override
  State<AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<AnalyzePage> {
  final controller = TextEditingController();
  List<WordTag> tags = [];
  bool analyzed = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'اكتب جملة عشان أحللها نحويًا...',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            if (controller.text.trim().isEmpty) return;
            setState(() {
              tags = analyze(controller.text);
              analyzed = true;
            });
          },
          icon: const Icon(Icons.account_tree),
          label: const Text('حلّل الجملة'),
        ),
        const SizedBox(height: 16),
        if (analyzed && tags.isNotEmpty) ...[
          const Text('التحليل:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((t) => Chip(
                  backgroundColor: t.color.withOpacity(0.15),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.word, style: TextStyle(fontWeight: FontWeight.bold, color: t.color)),
                      Text(t.tag, style: TextStyle(fontSize: 11, color: t.color)),
                    ],
                  ),
                )).toList(),
          ),
        ],
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'التحليل النحوي هنا تقديري بالقواعد. التحليل العميق (كل الحالات الإعرابية) ممكن يتضاف بعدين بموديل ذكاء اصطناعي بيشتغل على الجهاز.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== 4) الكاميرا: قراءة نص من الصورة + ترجمته (أوفلاين) ====================

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? controller;
  bool ready = false;
  bool busy = false;
  String recognized = '';
  String translated = '';
  bool arToEn = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) showMsg(context, 'مفيش كاميرا على الجهاز ده');
        return;
      }
      controller = CameraController(cams.first, ResolutionPreset.medium, enableAudio: false);
      await controller!.initialize();
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) showMsg(context, 'محتاج إذن الكاميرا: افتح إعدادات التطبيق واسمح بالكاميرا');
    }
  }

  Future<void> _captureAndRead() async {
    if (controller == null || busy || !ready) return;
    setState(() {
      busy = true;
      recognized = '';
      translated = '';
    });
    try {
      final img = await controller!.takePicture();
      final input = InputImage.fromFilePath(img.path);

      final latin = TextRecognizer(script: TextRecognitionScript.latin);
      final ar = TextRecognizer(script: TextRecognitionScript.arabic);
      final latinText = (await latin.processImage(input)).text;
      final arText = (await ar.processImage(input)).text;
      await latin.close();
      await ar.close();

      final best = arText.trim().length >= latinText.trim().length ? arText : latinText;
      setState(() {
        recognized = best.trim();
        arToEn = !isArabicText(best.trim());
      });
      if (best.trim().isEmpty && mounted) {
        showMsg(context, 'مفيش نت واضح في الصورة — جرب تقترب شوية');
      }
    } catch (e) {
      if (mounted) showMsg(context, 'حصل خطأ أثناء قراءة الصورة');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _translateCaptured() async {
    if (recognized.isEmpty) return;
    try {
      final tr = OnDeviceTranslator(
        sourceLanguage: arToEn ? TranslateLanguage.arabic : TranslateLanguage.english,
        targetLanguage: arToEn ? TranslateLanguage.english : TranslateLanguage.arabic,
      );
      final out = await tr.translateText(recognized);
      await tr.close();
      setState(() => translated = out);
    } catch (e) {
      if (mounted) showMsg(context, 'تأكد إن موديلات الترجمة اتنزلت (أول مرة محتاجة نت)');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 320,
          child: !ready
              ? const Center(child: CircularProgressIndicator())
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller!),
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FloatingActionButton(
                            onPressed: busy ? null : _captureAndRead,
                            child: Icon(busy ? Icons.hourglass_top : Icons.camera),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        const Text('النص المقروء من الصورة:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(recognized.isEmpty ? 'وجّه الكاميرا على نص (سؤال، جملة...) واضغط زرار الكاميرا' : recognized),
          ),
        ),
        if (recognized.isNotEmpty) ...[
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('عربي ← إنجليزي')),
              ButtonSegment(value: false, label: Text('إنجليزي ← عربي')),
            ],
            selected: {arToEn},
            onSelectionChanged: (s) => setState(() => arToEn = s.first),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _translateCaptured,
            icon: const Icon(Icons.translate),
            label: const Text('ترجم النص المقروء'),
          ),
        ],
        if (translated.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('الترجمة:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(translated, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'الكاميرا بتقرأ أي نص في الصورة وترجمه — كل ده أوفلاين على الجهاز. إنها "تفهم" الصورة وتجاوب على أسئلة عن محتواها (زي: إيه المطلوب في السؤال ده؟) محتاج موديل ذكاء اصطناعي ضخم — نقدر نضيفه كمرحلة جاية.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}
