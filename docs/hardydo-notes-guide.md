# Hardydo Notes: cài đặt và cách dùng

Hardydo Notes là app ghi chú cho macOS. Mọi note nằm trên máy; app không đồng bộ
lên mạng và không cần tài khoản. Toàn bộ chữ trong app là tiếng Anh; tài liệu này
ghi tên nút và menu đúng như trong app.

## Dữ liệu nằm ở đâu

Giống các app note khác trên macOS:

| Dữ liệu | Vị trí |
|---|---|
| Note (cả bản sao của file đã mở) | `~/Library/Application Support/com.hardydo.drivenotes/notes.json` |
| Nhóm note | `~/Library/Application Support/com.hardydo.drivenotes/groups.json` |
| Tab đang mở, tab đã ghim, mức phóng chữ, tỉ lệ chia đôi, lựa chọn bảng và xuất file | UserDefaults, domain `com.hardydo.drivenotes` (`~/Library/Preferences/com.hardydo.drivenotes.plist`) |

File JSON được ghi ở luồng nền, theo thứ tự, và được ghi hết trước khi app thoát.
Nếu ghi lỗi hoặc file note bị hỏng không đọc được, app hiện cảnh báo **Storage
Problem** thay vì lặng lẽ mất dữ liệu.

Mỗi lần lưu, bản cũ được giữ lại thành `notes.previous.json` (nhóm là
`groups.previous.json`), cùng thư mục. Nếu `notes.json` hỏng, app chép nó sang
`notes.unreadable-<số>.json` rồi đọc bản trước đó; nếu không chép ra được, phiên
đó được lưu vào `notes.recovered-<số>.json` để không ghi đè file hỏng. Muốn tự
khôi phục: thoát app, sao lưu cả thư mục, đổi tên file muốn dùng thành
`notes.json` (hoặc `groups.json`) rồi mở lại app.

Khi phát triển, đặt biến môi trường `HARDYDO_NOTES_DATA=<thư mục>` để app dùng
thư mục đó và bộ cài đặt riêng `com.hardydo.drivenotes.sandbox`, không đụng tới
note thật.

## Build và cài app

Cần Swift 6 (Command Line Tools là đủ, không cần Xcode).

```bash
cd hardydo-notes-app
./scripts/build-app.sh --install
```

App được build ra `dist/Hardydo Notes.app`. Với `--install`, app được chuyển
vào `~/Applications` và ghi đè bản đang cài; note và cài đặt vẫn giữ nguyên. Bỏ `--install` nếu chỉ muốn
build.

Nếu máy có chứng chỉ ký code `Hardydo Notes Dev` (tạo bằng
`./scripts/make-signing-cert.sh`), script dùng nó để ký; không có thì ký ad-hoc,
app vẫn chạy bình thường. Đặt biến `HARDYDO_SIGN_IDENTITY` để dùng tên khác.

Icon app lấy từ logo trong `Resources/brand/`. Sửa `Resources/AppIcon.svg` rồi
chạy `./scripts/make-icon.sh` (cần `rsvg-convert` từ Homebrew `librsvg`) để tạo
lại `Resources/AppIcon.icns`.

Chạy bộ kiểm tra logic (Swift Testing, Command Line Tools là đủ):

```bash
./scripts/test.sh
```

Script gọi `swift test` và chỉ rõ chỗ plugin macro của Swift Testing: với Command
Line Tools, `swift test` trần đôi khi báo `plugin for module 'TestingMacros' not
found` ngay sau khi sửa một file trong Core.

Các probe trong `Tools/probes/` chạy app thật trong cửa sổ ẩn để đo tốc độ và kiểm
tra kéo thả, dữ liệu, phiên tab; cách chạy xem `Tools/probes/README.md`.

### Cấu trúc mã nguồn

| Thư mục | Nội dung |
|---|---|
| `Sources/HardydoNotesCore/Notes` | Note, nhóm note, di chuyển ↑/↓ trong danh sách, danh sách tab (ghim, lịch sử tab đã đóng), tính chỗ thả khi kéo (`SidebarReorder`, `ReorderGeometry`, `ReorderTracker`) |
| `Sources/HardydoNotesCore/Persistence` | `NoteStore`, file note `NotesFile` (ghi nền, giữ bản trước), đọc/ghi file đã mở `LocalFileDisk`, cài đặt `Preferences`, đường dẫn dữ liệu |
| `Sources/HardydoNotesCore/Editing` | Nhận loại nội dung, tô màu cú pháp, gấp khối, vị trí dòng `LineIndex`, lệnh theo dòng, định dạng Markdown/JSON, mức phóng chữ |
| `Sources/HardydoNotesCore/Markdown` | Markdown → HTML, tô kiểu Markdown trong editor, tiêu đề cho breadcrumb `MarkdownOutline` |
| `Sources/HardydoNotesCore/Search` | Tìm trong note và mọi note `TextSearch`, tìm mờ và xếp hạng ⌘P |
| `Sources/HardydoNotes/App` | Điểm vào app (tạo store, file nhóm, cài đặt rồi đưa vào `AppModel`), `AppDelegate`, `InputMonitors` (phím, chuột giữa, cử chỉ phóng chữ), menu, kéo file vào |
| `Sources/HardydoNotes/Features/*` | Mỗi tính năng một thư mục: Tabs, Sidebar, Editor, Workspace (cả `LayoutSettings`), Preview, Find, Search, QuickOpen, Export |
| `Sources/HardydoNotes/Shared` | View và style dùng chung, phiên kéo thả `ReorderSession` |
| `Tests/HardydoNotesCoreTests` | Bộ kiểm tra chạy bằng `./scripts/test.sh` (`swift test`), mỗi file ứng với một kiểu trong Core |
| `Tools/probes` | Probe đo tốc độ và kiểm tra hành vi trên app thật |

Core không phụ thuộc SwiftUI nên kiểm tra được độc lập. Mỗi tính năng có model
riêng, nằm cạnh view của nó:

| Model | Giữ |
|---|---|
| `TabsModel` | Tab đang mở, tab đang chọn, ghim, đóng/mở lại, lưu/khôi phục tab |
| `SidebarModel` | Phiên kéo thả của danh sách note và file, trạng thái chọn của từng dòng |
| `GroupsModel` | Nhóm note và file `groups.json` |
| `WorkspaceEditor` | Editor của note đang mở: chế độ Editor/Split/Preview, loại nội dung, lệnh theo dòng, Go to Line, Format, khoá note, đồng bộ cuộn |
| `FindModel` | Thanh tìm/thay trong note và tuỳ chọn tìm (dùng chung với tìm mọi note) |
| `GlobalSearchModel`, `QuickOpenModel`, `DialogModel`, `LayoutSettings` | Tìm mọi note, bảng ⌘P, các hộp hỏi/cảnh báo, bố cục cửa sổ |

`AppModel` chỉ ghép các model lại và chạy những việc đi qua nhiều tính năng (tạo,
xoá, đổi tên note, mở file, lưu khi thoát). Mỗi view nhận model của tính năng
mình; việc cần tính năng khác đi qua một struct hành động nhỏ (`NoteRowActions`,
`TabActions`, `QuickOpenActions`). Khi đổi tab, `TabsModel` gọi hai hook mà
`AppModel` gắn trước khi khôi phục tab: `leaving` (lúc tab cũ còn đang chọn: đẩy
chữ đang gõ vào kho, bỏ kết quả tìm cũ) và `changed` (sau khi đổi: tô dòng ở
sidebar, nhận loại nội dung).

## Những điều nên biết

- **Danh sách note** bên trái có hai phần: **Notes** (note trong app) và
  **Open Files** (file trên máy mở bằng app). Note ghim nằm đầu phần của nó.
- **Lưu**: app tự lưu sau khi bạn ngừng gõ; ⌘S lưu ngay. Chữ đang gõ được đưa vào
  kho khi bạn dừng tay khoảng 1/4 giây, khi đổi tab, khi chuyển sang app khác và
  khi thoát. Nếu lúc thoát app không ghi được dữ liệu (ổ đầy, thư mục bị khoá…),
  app hỏi **Don’t Quit** hay **Quit Anyway** thay vì thoát luôn.
- **Xoá note** (nút ✕ khi rê chuột, bấm nút giữa chuột vào note, chuột phải →
  **Delete Note…**, hoặc phím Delete; với file đã mở thì các cách này chỉ đóng file): hỏi trước rồi xoá hẳn, không khôi phục được. Trong hộp hỏi, Return
  chọn **Cancel** cho an toàn; ⌘⌫ mới là **Delete**, Esc để huỷ. Note đang khoá
  thì phải mở khoá trước.
- **Gom nhóm note** (giống nhóm tab của Edge): chuột phải vào note → **Add to
  Group** → **New Group** hoặc một nhóm có sẵn; hoặc kéo thả (xem **Kéo thả**).
  Bấm tên nhóm để thu gọn hoặc mở. Nút **+** tạo note mới trong nhóm; nút bút chì
  (hoặc chuột phải vào tên nhóm) để đổi tên, chọn màu, tạo note mới trong nhóm
  hay **Ungroup**. Bỏ nhóm thì các note vẫn còn nguyên; nhóm không còn note nào
  tự biến mất. Nhóm ghim được (**Pin Group to Top**): nhóm đã ghim nằm trên cùng
  cùng các note đã ghim. Ghim một note trong nhóm chỉ đưa note đó lên đầu nhóm;
  khi mọi note trong nhóm đều đã ghim thì nhóm tự được ghim.
- **Breadcrumb** (thanh dưới tab, giống VS Code): note trong app hiện
  `Hardydo Notes › nhóm › note`, file đã mở hiện từng thư mục trong đường dẫn rồi
  tới tên file. Với Markdown, phía sau là các heading bao quanh con trỏ, cập nhật
  khi di con trỏ. Tên note không còn hiện trên thanh tiêu đề cửa sổ, nên kéo ở chỗ
  trống trên thanh đó là di chuyển được cửa sổ.
- **Đổi tên note** (chuột phải vào note hoặc tab → **Rename…**): chỉ cho note
  trong app. Tên đặt tay thay cho dòng đầu; để trống thì quay lại lấy dòng đầu.
  File mở từ ổ đĩa luôn mang tên file.
- **Icon file**: tab và breadcrumb chỉ có icon tài liệu khi note là file thật trên
  máy; note tạm trong app không có icon.
- **Xoá note trống** (nút thùng rác giữa Search và New Note): xoá mọi note trong app
  hoàn toàn không có chữ (hiện là “Untitled”). Note có dù chỉ một dòng và note
  đang khoá đều được giữ lại; không khôi phục được.
- **Chuột phải vào tab** cũng có **Lock (Read-Only)** / **Unlock** và **Rename…**.
- **Con trỏ gõ chữ** trượt mượt tới vị trí mới (giống tuỳ chọn smooth caret của
  VS Code), đứng yên khi đang di chuyển và nhấp nháy khi dừng.
- **Khoá note** (nút ổ khoá hoặc ⌥⌘L): note chỉ xem được, không sửa, định dạng
  hay xoá được cho tới khi mở khoá. Con trỏ nhập vẫn hiện và di chuyển bằng
  phím mũi tên / ⌘↑ ⌘↓ như bình thường để chọn và copy.
- **Ghim note** (chuột phải → **Pin Note to Top**): note ghim luôn nằm đầu danh
  sách bên trái, có icon ghim. Việc này khác với ghim tab (xem dưới).
- **Kéo thả** (giống tab của Edge): nhấn chuột là note / tab được chọn ngay; kéo
  thì chính dòng đó nhấc lên (nền đặc, có bóng) đi theo chuột, các dòng khác trượt
  sang nhường chỗ, thả ra thì nó vào chỗ trống. Dữ liệu chỉ ghi một lần lúc thả.
  - Kéo note vào giữa các note của một nhóm (hoặc ngay dưới tên nhóm đang mở) thì
    note vào nhóm đó; kéo ra ngoài nhóm thì note rời nhóm. Ở khe cuối nhóm: nửa
    trên là vào nhóm (thành note cuối, dòng thụt vào và thanh màu dài ra), nửa
    dưới là đứng ngoài ngay dưới nhóm. Nhấc note cuối của nhóm lên thì nó vẫn
    trong nhóm cho tới khi kéo xuống quá giữa khe.
  - Nhóm đang thu gọn: thả note lên giữa tên nhóm (tên nhóm có viền màu nhấn) để
    cho note vào nhóm; thả trên hoặc dưới tên nhóm thì chỉ đổi chỗ.
  - Kéo tên nhóm để chuyển cả nhóm cùng mọi note của nó; nhóm không thả vào giữa
    nhóm khác được.
  - Note / nhóm thường không kéo lên trên phần đã ghim, và ngược lại; tab cũng vậy.
  - Kéo tới sát mép trên hoặc dưới danh sách thì danh sách tự cuộn. Bấm Esc trong
    lúc kéo để huỷ, dòng về chỗ cũ.
  - Kéo file từ Finder thả vào danh sách để mở file đó.
  - Note mới nằm ngay dưới các note ghim.
- **Tab** (giống VS Code): bấm một note trong danh sách để mở ở tab tạm (tên in
  nghiêng); bấm note khác thì tab tạm được thay. Sửa note, nhấp đúp vào note hoặc
  tab, hay ⌘S thì tab được giữ lại. Note mới, file mở từ máy và **Open in New
  Tab** luôn mở tab riêng. Nhấp đúp vào chỗ trống trên thanh tab (bên phải các
  tab) để tạo note mới. Kéo tab để đổi thứ tự (xem **Kéo thả**). Đóng tab
  không xoá note. Các
  tab đang mở và tab đã ghim được nhớ cho lần mở app sau.
  - **Đóng tab**: ⌘W, bấm nút giữa chuột vào tab, hoặc nút ✕. Không còn tab thì
    ⌘W đóng cửa sổ.
  - **Mở lại tab vừa đóng**: ⇧⌘T (nhớ 20 tab gần nhất, mở lại đúng chỗ cũ, tab
    đã ghim mở lại vẫn ghim).
  - **Ghim tab**: chuột phải vào tab → **Pin Tab**. Tab ghim luôn nằm đầu thanh
    tab, có icon ghim thay cho nút ✕ (bấm icon để bỏ ghim). ⌘W, nút giữa chuột,
    **Close Other Tabs**, **Close Tabs to the Right** và **Close All Tabs** không
    đóng tab ghim (các lệnh này mờ đi khi chỉ còn tab ghim); muốn đóng thì
    **Unpin Tab** trước.
  - Chuột phải vào tab còn có **Keep Tab Open**, **Close Tab**, **Close Other
    Tabs**, **Close Tabs to the Right**, **Close All Tabs**, **Reopen Closed Tab**.
- **Go to Note** (⌘P): ô tìm kiếm mờ theo tên note, mũi tên lên/xuống để chọn,
  Enter để mở, Esc để đóng. Gõ `:` rồi số dòng để nhảy tới dòng đó (giống ⌃G).
  Giống Cursor / VS Code, ô này tự đóng khi làm việc khác: bấm ra ngoài, dùng
  phím tắt của lệnh khác (⌘N, ⌘B, ⌘W…, lệnh đó vẫn chạy), mở thanh menu hoặc
  chuyển sang app khác. ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z vẫn dùng cho chữ trong ô.
- **Tự nhận ra loại nội dung** (giống VS Code): file mở từ máy theo đuôi file;
  note trong app thì app đoán theo nội dung, mặc định là Markdown. Nhận ra
  Markdown, JSON, JavaScript, TypeScript, Python, HTML, XML, CSS, YAML, SQL,
  Shell, Swift và văn bản thường (`.txt`). Vùng **Editor** tô màu cú pháp theo
  bảng màu Dark+ của VS Code (app chỉ có giao diện tối, kể cả khi macOS
  đang ở chế độ sáng); trong Markdown, khối code có ghi ngôn
  ngữ (```` ```json ````, ```` ```py ````…) cũng được tô theo ngôn ngữ đó. App
  chỉ đổi sang loại code khi nội dung rõ ràng là code, nên ghi chú kiểu
  `[ ] mua sữa`, `Wifi: abc` hay `Update CV` vẫn là Markdown. Trong lúc gõ, loại
  nội dung được đoán lại ở luồng nền sau khi bạn dừng tay. Note dài quá khoảng
  500 KB, hoặc có một dòng dài quá 20.000 ký tự (ví dụ JSON nén một dòng), thì
  không tô màu để gõ vẫn mượt.
- **Thanh công cụ** đổi theo loại nội dung: Markdown có nút tiêu đề, đậm,
  nghiêng, gạch ngang, code, danh sách, danh sách số, checklist, trích dẫn,
  liên kết và menu **Insert** (bảng, đường kẻ ngang). **Table…** (⌥⌘T) hỏi số
  cột và số hàng (không tính dòng tiêu đề), app nhớ lựa chọn cho lần sau. Note
  code chỉ hiện tên loại nội dung; JSON có thêm nút **Format** (⇧⌥F) để thụt lề
  lại cho dễ đọc, giữ nguyên thứ tự key, ⌘Z hoàn tác được (dùng ở Editor hoặc
  Split, không dùng ở Preview). JSON sai cú pháp thì app báo lỗi và không sửa gì.
- **Preview** (⌥⌘3) và **Split** (⌥⌘2): Markdown hiện thành trang kiểu GitHub;
  note code hiện thành một khối code tô màu; văn bản thường hiện nguyên như gõ.
  Liên kết trong Preview chỉ mở với `http`, `https` và `mailto`. Kéo đường chia
  để đổi độ rộng, tỉ lệ được nhớ cho mọi note. Note dài quá 100.000 ký tự thì
  Preview không tô màu code (HTML/PDF xuất ra vẫn tô tới 500.000 ký tự).
  - **Sync Scroll** (icon ↑↓ cạnh Editor / Split / Preview, chỉ hiện ở Split):
    bật (icon xanh) thì cuộn bên nào bên kia cũng chạy theo, khớp theo dòng
    nguồn: dòng ở đầu editor là khối ở đầu preview. Gõ chữ thì preview tự canh
    lại theo editor. Mặc định bật, trạng thái được nhớ.
- **Export** (⇧⌘S): lưu note đang mở ra đúng loại của nó (ví dụ `.md`, `.json`),
  trang web (.html) hoặc PDF (luôn nền sáng). highlight.js được đóng gói sẵn
  trong app nên Preview, HTML và PDF đều tô màu code khi không có mạng; file
  .html xuất ra tự chứa đủ, mở ở máy khác cũng không cần mạng.
- **Find** (⌘F): thanh tìm kiếm hiện trên vùng soạn, tô vàng mọi chỗ khớp, chỗ
  đang chọn tô cam, kèm số thứ tự "3 / 12". Ba nút bên phải ô tìm: **Aa** (Match
  Case), **ab** (Match Whole Word), **.\*** (Use Regular Expression). Enter hoặc
  ⌘G sang kết quả sau, Shift+Enter hoặc ⇧⌘G về kết quả trước, Esc đóng. ⌥⌘F (hoặc
  mũi tên bên trái) hiện ô thay thế: **Replace** thay chỗ đang chọn rồi sang chỗ
  sau, **Replace All** thay mọi chỗ; ⌘Z hoàn tác. Khi bật regex, ô thay dùng được
  `$1`, `$2`… Đang bôi đen chữ rồi bấm ⌘F thì chữ đó được điền sẵn. Việc tìm chạy
  ở luồng nền và chỉ chạy khi bạn ngừng gõ một chút, nên gõ không bị khựng; tối đa 10.000 chỗ khớp, và khi bật regex thì
  dòng dài quá 10.000 ký tự được bỏ qua.
- **Search All Notes** (⇧⌘F, hoặc nút kính lúp cạnh chữ "Notes"): danh sách bên
  trái đổi thành kết quả, nhóm theo note, mỗi dòng có số dòng và đoạn chữ quanh
  chỗ khớp. Bấm một dòng để mở note và nhảy tới đúng chỗ đó. Bấm ⇧⌘F lần nữa,
  Esc hoặc nút ✕ để quay về danh sách. Kết quả hiện khoảng 0,15 giây sau khi bạn
  dừng gõ; mỗi note hiện tối đa 50 dòng, tổng cộng tối đa 2.000 dòng.
- **Mở file trên máy**: chuột phải vào file văn bản hoặc code → **Open With →
  Hardydo Notes**, kéo file thả vào danh sách, hoặc **File → Open…** (⌘O). App
  sửa thẳng file đó (tự lưu sau khi bạn ngừng gõ, giữ nguyên bảng mã và tag
  Finder). File tối đa 5 MB. Nút ✕ (hoặc chuột phải → **Close File**, hay phím
  Delete) chỉ bỏ file khỏi danh sách, file vẫn còn trên máy. Nếu app khác sửa
  file trong lúc bạn cũng đang sửa, app hỏi **Keep My Version** hay **Use Version
  on Disk** thay vì ghi đè.
- **Lệnh theo dòng** (menu **Selection**, giống VS Code): di chuyển, nhân đôi,
  xoá, chèn dòng, thụt lề và comment áp dụng cho mọi dòng có trong vùng chọn;
  ⌘Z hoàn tác. Không bôi đen gì mà ⌘C / ⌘X thì chép / cắt cả dòng. Comment dùng
  đúng cú pháp của loại nội dung (`//`, `#`, `--`, `<!-- -->`…). Các lệnh này giữ
  nguyên kiểu xuống dòng của file (LF, CRLF của Windows hay CR).
- **Số dòng**: vùng soạn có cột số dòng bên trái, dòng đang đặt con trỏ được tô
  màu nhấn.
- **Gấp khối** (theo thuật toán của VS Code): mũi tên ở cột số dòng tại các dòng
  mở đầu một khối; bấm để gấp, dòng đầu có nút **⋯** (bấm để mở lại). Khối theo
  cặp ngoặc với JSON, JavaScript, TypeScript, CSS, Swift; theo thụt lề với
  Python, YAML, HTML, XML, SQL, Shell; theo tiêu đề, khối code, danh sách, bảng
  với Markdown; đều hỗ trợ `#region`. Sửa chữ hay tìm kiếm nhảy vào khối đang gấp
  thì khối tự mở.
- **Mỗi tab giữ trạng thái riêng**: khối đang gấp, vị trí cuộn và lịch sử hoàn
  tác (⌘Z) của từng tab còn nguyên khi đổi qua lại giữa các tab; đóng tab thì
  mất.
- **Giữ thụt lề khi xuống dòng**: Enter tạo dòng mới thụt vào bằng dòng đang gõ.
- **Phóng to, thu nhỏ chữ**: giữ ⌘ rồi lăn chuột, hoặc chụm/mở hai ngón trên
  trackpad, khi con trỏ nằm trên vùng soạn hoặc vùng xem; hoặc ⌘= / ⌘- / ⌘0. Mức
  phóng đi theo nấc 5%, từ 60% đến 300%, dùng chung cho mọi note và được nhớ.
- Vùng **Editor** dùng font monospace, chỉ đổi màu chứ không đổi cỡ chữ, nên tiêu
  đề và chữ thường thẳng hàng như trong VS Code.

## Phím tắt

Theo VS Code trên macOS. ⌘B giống VS Code: đang gõ trong note Markdown thì in
đậm, còn lại (focus ở sidebar, Preview, note code, chưa mở note) thì ẩn/hiện
danh sách bên trái; ⌃⌘S ẩn/hiện danh sách ở mọi nơi. Chưa mở note nào thì vùng
bên phải hiện logo app và các phím tắt chính, bấm vào dòng nào cũng chạy được.

### File và tab

| Phím | Tác dụng |
|---|---|
| ⌘N | New Note |
| ⌘O | Open… (file trên máy) |
| ⌘P | Go to Note… |
| ⌘S | Save |
| ⇧⌘S | Export… |
| ⌘W / nút giữa chuột | Close Tab (không đóng tab ghim; hết tab thì đóng cửa sổ) |
| ⌥⌘W | Close Other Tabs |
| ⇧⌘T | Reopen Closed Tab |
| ⌥⌘→ / ⌥⌘← | Next / Previous Tab |
| ⇧⌘] / ⇧⌘[ | Next / Previous Tab |
| ⌃⇥ / ⌃⇧⇥ | Next / Previous Tab |
| ⌃1 … ⌃8 | Tab thứ 1 … 8 |
| ⌃9 | Tab cuối cùng |
| ⌥⌘L | Lock or Unlock Note |
| ⌃⌘S | Ẩn / hiện danh sách bên trái |
| ⌘B | Ẩn / hiện danh sách bên trái (khi không gõ trong note Markdown) |

### Tìm kiếm và di chuyển

| Phím | Tác dụng |
|---|---|
| ⌘F / ⌥⌘F | Find / Find and Replace |
| ⌘G / ⇧⌘G | Find Next / Find Previous |
| ⇧⌘F | Search All Notes |
| ⌃G | Go to Line… |

### Soạn thảo (menu Selection)

Các phím trong menu **Selection** và **Format** chỉ chạy khi con trỏ đang ở vùng
soạn, nên ⌘1, ⌘L… không đụng tới ô tìm kiếm hay danh sách (⌘B ở ngoài vùng soạn
là ẩn/hiện danh sách).

| Phím | Tác dụng |
|---|---|
| ⌘L | Select Line |
| ⌥↑ / ⌥↓ | Move Line Up / Down |
| ⇧⌥↑ / ⇧⌥↓ | Copy Line Up / Down |
| ⇧⌘K | Delete Line |
| ⌘↩ / ⇧⌘↩ | Insert Line Below / Above |
| ⌘] / ⌘[ | Indent / Outdent Line |
| ⌘/ | Toggle Line Comment |

### Hiển thị

| Phím | Tác dụng |
|---|---|
| ⌥⌘1 / ⌥⌘2 / ⌥⌘3 | Editor / Editor and Preview / Preview |
| ⇧⌘V | Toggle Preview |
| ⌘= / ⌘- / ⌘0 | Zoom In / Zoom Out / Actual Size |
| ⌘ + lăn chuột, chụm trackpad | Phóng to / thu nhỏ chữ |
| ⌥⌘[ / ⌥⌘] | Fold / Unfold |
| ⇧⌥⌘[ / ⇧⌥⌘] | Fold All / Unfold All |

### Định dạng (menu Format)

| Phím | Tác dụng |
|---|---|
| ⌘B / ⌘I / ⇧⌘X | Bold / Italic / Strikethrough |
| ⌘E / ⌘K | Inline Code / Link |
| ⌘1 / ⌘2 / ⌘3 | Heading 1–3 |
| ⇧⌘8 / ⇧⌘7 / ⇧⌘L | Bulleted List / Numbered List / Checklist |
| ⇧⌘. | Quote |
| ⌥⌘T / ⌥⌘- | Insert Table… / Insert Horizontal Rule |
| ⇧⌥F | Format JSON |
