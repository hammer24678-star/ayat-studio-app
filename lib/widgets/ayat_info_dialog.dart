// Shared "about this app" dialog — shown from both the welcome screen's
// «معرفة المزيد عن التطبيق» link and the studio's app-bar (i) button, so
// the copy only lives in one place.
import 'package:flutter/material.dart';

import '../theme/ayat_theme.dart';

void showAyatInfoDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AyatColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AyatColors.hairline),
      ),
      title: const Text('عن استوديو الآيات ✦'),
      content: SingleChildScrollView(
        child: Text(
          'تطبيق مونتاج مخصص فقط لتصميم مقاطع الفيديو القرآنية — كل خيار فيه '
          'مبني لخدمة الآية والتلاوة.\n\n'
          '• تعرّف تلقائي بالذكاء الاصطناعي على الآية من الصوت (ميكروفون مباشر، '
          'أو صوت فيديو مرفوع)\n'
          '• «المزامنة التلقائية»: تحليل الفيديو كاملاً واكتشاف كل آية والزمن الذي '
          'قيلت فيه، ثم كتابتها بأنيميشن أثناء العرض والتصدير — تمامًا مع توقيت الشيخ\n'
          '• اختيار يدوي لأي آية من القرآن كاملاً (6,236 آية مضمّنة داخل التطبيق، '
          'تعمل بدون إنترنت)، أو كتابة نص مخصص\n'
          '• خلفيات جاهزة أو صورة خاصة، وإزالة كروم حقيقية للفيديوهات المصوّرة أمام '
          'خلفية ملوّنة (أي لون، مع تحكم بالقوة والنعومة)\n'
          '• تلاوات مرفقة لعدد من القرّاء مع معاينة صوتية\n'
          '• قوالب نصية جاهزة وتحكم كامل بالخط (مع رفع خطوط مخصصة) والحجم واللون '
          'والموضع والترجمة\n'
          '• بسملة افتتاحية وخاتمة كشاشتين مستقلتين قبل/بعد المقطع\n'
          '• قص ملتزم بحدود الآيات كما رصدها التعرّف الصوتي\n'
          '• تصدير MP4 حقيقي حتى 1080p ولمدة تصل إلى دقيقتين، بنسبة 9:16 أو 1:1\n\n'
          'يعمل التعرّف بنموذج Whisper على جهازك (يُنزَّل مرة واحدة عند أول '
          'استخدام)، مع محرك مطابقة عربي يقارن مع القرآن الكريم كاملاً.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق')),
      ],
    ),
  );
}
