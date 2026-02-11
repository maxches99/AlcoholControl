import WidgetKit
import SwiftUI

@main
struct AlcoholControlWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlcoholControlWidget()
        if #available(iOSApplicationExtension 16.2, *) {
            AlcoholControlLiveActivityWidget()
        }
    }
}
