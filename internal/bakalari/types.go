package bakalari

// Subject represents a school subject.
type Subject struct {
	ID     string `json:"Id"`
	Abbrev string `json:"Abbrev"`
	Name   string `json:"Name"`
}

// Teacher represents a school teacher.
type Teacher struct {
	ID   string `json:"Id"`
	Name string `json:"Name"`
}

// Hour represents a time slot in the timetable.
type Hour struct {
	ID        int    `json:"Id"`
	Caption   string `json:"Caption"`
	BeginTime string `json:"BeginTime"`
	EndTime   string `json:"EndTime"`
}

// Atom represents a single lesson in a timetable day.
type Atom struct {
	HourID    int    `json:"HourId"`
	SubjectID string `json:"SubjectId"`
	TeacherID string `json:"TeacherId"`
	Room      string `json:"Room"`
	Theme     string `json:"Theme"`
}

// Day represents a day in the timetable.
type Day struct {
	DayOfWeek int    `json:"DayOfWeek"`
	Date      string `json:"Date"`
	Atoms     []Atom `json:"Atoms"`
}

// TimetableResponse is the root object for the timetable API.
type TimetableResponse struct {
	Days     []Day     `json:"Days"`
	Hours    []Hour    `json:"Hours"`
	Subjects []Subject `json:"Subjects"`
	Teachers []Teacher `json:"Teachers"`
}

// Homework represents a homework assignment.
type Homework struct {
	ID      string `json:"ID"`
	Content string `json:"Content"`
	DateEnd string `json:"DateEnd"`
	Subject struct {
		Abbrev string `json:"Abbrev"`
	} `json:"Subject"`
	IsDone bool `json:"IsDone"`
}

// HomeworksResponse is the root object for the homeworks API.
type HomeworksResponse struct {
	Homeworks []Homework `json:"Homeworks"`
}

// Mark represents a single grade.
type Mark struct {
	MarkText string `json:"MarkText"`
	Caption  string `json:"Caption"`
	Date     string `json:"MarkDate"`
	Weight   int    `json:"Weight"`
	IsNew    bool   `json:"IsNew"`
}

// SubjectMarks represents marks for a specific subject.
type SubjectMarks struct {
	Subject     Subject `json:"Subject"`
	AverageText string  `json:"AverageText"`
	Marks       []Mark  `json:"Marks"`
}

// MarksResponse is the root object for the marks API.
type MarksResponse struct {
	Subjects []SubjectMarks `json:"Subjects"`
}

// AbsenceDay represents a daily absence summary.
type AbsenceDay struct {
	Date     string `json:"Date"`
	Ok       int    `json:"Ok"`
	Missed   int    `json:"Missed"`
	Late     int    `json:"Late"`
	Soon     int    `json:"Soon"`
	Unsolved int    `json:"Unsolved"`
}

// AbsenceResponse is the root object for the absence API.
type AbsenceResponse struct {
	Absences []AbsenceDay `json:"Absences"`
}

// UserInfo represents the student profile.
type UserInfo struct {
	UserUID  string `json:"UserUID"`
	FullName string `json:"FullName"`
	Class    struct {
		Name    string `json:"Name"`
		Teacher struct {
			Name string `json:"Name"`
		} `json:"Teacher"`
	} `json:"Class"`
}
