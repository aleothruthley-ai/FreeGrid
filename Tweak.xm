#import <UIKit/UIKit.h>

// 声明我们要用到的方法，防止编译警告
@interface SBIconListView : UIView
- (NSString *)iconLocation;
@end

// ===================================================================
// 1. 视图层 (View Layer)
// ===================================================================
%hook SBIconListView

// 强制视图层允许出现间隙 (Gaps)
// 这会让用户在拖拽图标放下时，精准停在手指所在的网格，而不是被系统强行吸附到末尾。
- (BOOL)allowsGaps {
    // 保护机制：如果是底部的 Dock 栏，千万不要允许间隙，否则 Dock 排版会乱掉
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        if ([location containsString:@"Dock"]) {
            return %orig;
        }
    }
    return YES;
}

%end


// ===================================================================
// 2. 数据模型层 (Model Layer)
// ===================================================================
%hook SBIconListModel

// 允许当前列表存在"固定位置"的图标
- (BOOL)allowsFixedIconLocations {
    return YES;
}

// 强制开启系统底层的固定位置行为 (1 = Enabled)
- (long long)fixedIconLocationBehavior {
    return 1;
}

// ===================================================================
// 3. 拦截网格挤压与修复 (彻底解决图标被系统推挤的问题)
// ===================================================================

// 欺骗系统：告诉它当前的网格布局永远是“合法且完美”的
// 这样系统就不会在后台偷偷运行“挤压排版”审计了
- (BOOL)isGridLayoutValid {
    return YES;
}

- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options {
    return YES;
}

- (BOOL)isGridLayoutValid:(id)arg1 {
    return YES;
}

- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)icons {
    return YES;
}

// 【关键修复处】：拦截挤压修复方法。
// 直接返回 nil，告诉系统“没有发生任何改变，不需要替换”。
// 绝对不能返回 self，否则会引发 -[SBIconListModel count] 的崩溃！
- (id)_updateModelByRepairingGapsIfNecessary {
    return nil;
}

- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons {
    return nil;
}

// 拦截带参数的底层修补算法，直接原样返回传入的数组，拒绝清除空隙
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoidingIcons {
    return icons; 
}

%end
