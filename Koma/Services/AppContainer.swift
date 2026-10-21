import Foundation
import SwiftData

/// アプリ全体で共有する SwiftData のコンテナ。通知のアクション処理からも使う。
enum AppContainer {
    static let schema = Schema([
        Semester.self,
        Course.self,
        Meeting.self,
        TaskItem.self,
        Exam.self,
        MakeupClass.self,
    ])

    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema)]
            )
        } catch {
            // 保存先が開けない場合でもアプリが起動できるよう、メモリ上に退避する。
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("データの保存領域を初期化できませんでした: \(error)")
            }
        }
    }()

    /// 最初の描画より前に学期を用意する。描画後に差し込むと、
    /// 空の状態から中身ありへ入れ替わるときにスクロール位置がずれる。
    @MainActor
    static func seedIfNeeded() {
        let context = shared.mainContext
        let existing = (try? context.fetch(FetchDescriptor<Semester>())) ?? []
        SeedService.ensureSemesterExists(in: context, existing: existing)
    }
}
