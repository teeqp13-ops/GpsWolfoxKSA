#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
echo -e "${GREEN}GPS Full Integrated Installer${NC}"
echo "هذا السكربت يجهز ملفات المشروع، يضبط الربط، ويتحقق من السيرفر والبناء."

chmod +x scripts/*.sh tools/*.sh 2>/dev/null || true
mkdir -p packages server/storage/uploads/devices server/storage/exports server/storage/backups server/storage/logs
chmod -R 775 server/storage 2>/dev/null || true

echo -e "\n${BLUE}[1] فحص الملفات${NC}"
./tools/verify_all.sh || true

echo -e "\n${BLUE}[2] إعداد ربط API داخل ملف iOS${NC}"
read -r -p "أدخل رابط API مثل https://domain.com/gps/server/public/api أو اتركه كما هو: " API_URL || true
read -r -p "أدخل مفتاح API من لوحة التحكم أو اتركه كما هو: " API_KEY || true
if [ -n "${API_URL:-}" ]; then
  python3 - <<'PYINNER_URL' "$ROOT/Sources/GPSApiClient.mm" "$API_URL"
import sys,re,pathlib
p=pathlib.Path(sys.argv[1]); val=sys.argv[2].rstrip('/')
s=p.read_text()
s=re.sub(r'c\.baseURL=@"[^"]*";', f'c.baseURL=@"{val}";', s)
p.write_text(s)
print('تم تحديث رابط API')
PYINNER_URL
fi
if [ -n "${API_KEY:-}" ]; then
  python3 - <<'PYINNER_KEY' "$ROOT/Sources/GPSApiClient.mm" "$API_KEY"
import sys,re,pathlib
p=pathlib.Path(sys.argv[1]); val=sys.argv[2]
s=p.read_text()
s=re.sub(r'c\.apiKey=@"[^"]*";', f'c.apiKey=@"{val}";', s)
p.write_text(s)
print('تم تحديث مفتاح API')
PYINNER_KEY
fi

echo -e "\n${BLUE}[3] معلومات تنصيب السيرفر${NC}"
echo "ارفع مجلد server إلى الاستضافة، ثم افتح:"
echo "  https://YOUR-DOMAIN/server/public/install.php"
echo "أو إذا رفعت المشروع كاملًا افتح:"
echo "  https://YOUR-DOMAIN/install.php"

echo -e "\n${BLUE}[4] البناء${NC}"
if [ -n "${THEOS:-}" ]; then
  read -r -p "هل تريد بناء Rootless الآن؟ y/N: " BUILD_NOW || true
  if [[ "${BUILD_NOW:-}" =~ ^[Yy]$ ]]; then
    ./scripts/build-rootless.sh
  fi
else
  echo "THEOS غير مضبوط. للبناء لاحقًا نفذ: ./scripts/build-rootless.sh"
fi

echo -e "\n${GREEN}انتهى التجهيز.${NC}"
