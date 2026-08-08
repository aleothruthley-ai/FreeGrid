#import <UIKit/UIKit.h>

// 声明 iOS 底层私有方法，防止编译报错
@interface SBIconListView : UIView
- (NSString *)iconLocation;
@end

@interface SBIconListModel : NSObject
- (void)saveCurrentIconLocationsAsFixed;
@end

// ===================================================================
// 1. 视图层：允许桌面网格存在空隙 (Gaps)
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        // 核心防御：绝对不能让底部的 Dock 栏允许空隙，否则 Dock 会排版错乱
        if (location && [location containsString:@"Dock"]) {
            return %orig;
        }
    }
    return YES; // 让普通桌面视图支持图标间留出空位
}

%end

// ===================================================================
// 2. 数据层：接管并锁死系统原生的位置记录
// ===================================================================
%hook SBIconListModel

// 允许数据模型记录图标的"固定位置"
- (BOOL)allowsFixedIconLocations {
    return YES;
}

// 【关键修复：彻底解决安全模式和无法移动的问题】
// 系统每次布局都会调用这个方法试图消除空隙(把图标往左上角推)。
// 我们拦截它，并**直接把系统传进来的 icons 数组原样返回**！
// 既不破坏底层数据结构类型，又完美阻断了自动靠拢。
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoidingIcons {
    return icons; 
}

// 以下操作：只要桌面上的图标发生了增、删、移、换，
// 立刻调用苹果原生的 saveCurrentIconLocationsAsFixed，
// 让系统乖乖地把当前所有图标所在的坑位坐标写入 IconState.plist 中永久保存！

- (void)didAddIcon:(id)icon options:(unsigned long long)options {
    %orig;
    if ([self respondsToSelector:@selector(saveCurrentIconLocationsAsFixed)]) {
        [self saveCurrentIconLocationsAsFixed];
    }
}

- (void)didRemoveIcon:(id)icon options:(unsigned long long)options {
    %orig;
    if ([self respondsToSelector:@selector(saveCurrentIconLocationsAsFixed)]) {
        [self saveCurrentIconLocationsAsFixed];
    }
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    %orig;
    if ([self respondsToSelector:@selector(saveCurrentIconLocationsAsFixed)]) {
        [self saveCurrentIconLocationsAsFixed];
    }
}

- (id)replaceIcon:(id)icon withIcon:(id)replacementIcon options:(unsigned long long)options {
    id result = %orig;
    if ([self respondsToSelector:@selector(saveCurrentIconLocationsAsFixed)]) {
        [self saveCurrentIconLocationsAsFixed];
    }
    return result;
}

%end
